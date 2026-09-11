public with sharing class KudosService {
  public class KudosLimitException extends Exception {
  }

  @AuraEnabled
  public static Kudo__c giveKudo(
    Id recipientId,
    Id badgeTypeId,
    String message
  ) {
    try {
      Id giverId = UserInfo.getUserId();

      if (recipientId == giverId) {
        throw new KudosLimitException('You cannot give a kudo to yourself.');
      }

      Integer maxPerDay = getMaxKudosPerDay();
      Integer givenToday = [
        SELECT COUNT()
        FROM Kudo__c
        WHERE Giver__c = :giverId AND CreatedDate = TODAY
        WITH USER_MODE
      ];
      if (givenToday >= maxPerDay) {
        throw new KudosLimitException(
          'You have reached your daily kudos limit of ' + maxPerDay + '.'
        );
      }

      Kudo__c kudo = new Kudo__c(
        Recipient__c = recipientId,
        Giver__c = giverId,
        Badge_Type__c = badgeTypeId,
        Message__c = message
      );
      Database.insert(kudo, AccessLevel.USER_MODE);
      return kudo;
    } catch (KudosLimitException e) {
      throw wrapForClient(e.getMessage());
    } catch (DmlException e) {
      throw wrapForClient(
        'Unable to save this kudo. Please check the recipient and badge type and try again.'
      );
    } catch (QueryException e) {
      throw wrapForClient(
        'Unable to give this kudo right now. Please try again.'
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Kudo__c> getRecentKudos(Integer numberOfRecords) {
    try {
      Integer recordLimit = numberOfRecords != null ? numberOfRecords : 20;
      return [
        SELECT
          Id,
          Message__c,
          CreatedDate,
          Recipient__r.Name,
          Giver__r.Name,
          Badge_Type__r.Name,
          Badge_Type__r.Icon_Name__c
        FROM Kudo__c
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT :recordLimit
      ];
    } catch (QueryException e) {
      throw wrapForClient('Unable to load the kudos wall right now.');
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Badge_Type__c> getActiveBadgeTypes() {
    try {
      return [
        SELECT Id, Name, Icon_Name__c, Points_Value__c
        FROM Badge_Type__c
        WHERE Active__c = TRUE
        WITH USER_MODE
        ORDER BY Name
      ];
    } catch (QueryException e) {
      throw wrapForClient('Unable to load badge types right now.');
    }
  }

  private static Integer getMaxKudosPerDay() {
    Kudos_Settings__c settings = Kudos_Settings__c.getInstance();
    return settings.Max_Kudos_Per_Day__c != null
      ? Integer.valueOf(settings.Max_Kudos_Per_Day__c)
      : 5;
  }

  private static AuraHandledException wrapForClient(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
