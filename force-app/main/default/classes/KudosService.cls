public with sharing class KudosService {
  public class KudosLimitException extends Exception {
  }

  public class KudoWallItem {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String recipientName;
    @AuraEnabled
    public String giverName;
    @AuraEnabled
    public String badgeName;
    @AuraEnabled
    public String badgeIcon;
    @AuraEnabled
    public String tierLabel;
    @AuraEnabled
    public String tierIcon;
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

      Kudos_Settings__c settings = Kudos_Settings__c.getInstance();

      if (!settings.Can_Give_Kudos__c) {
        throw new KudosLimitException(
          'Giving kudos is currently disabled for your account.'
        );
      }

      Integer maxPerDay = getMaxKudosPerDay(settings);
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
  public static List<KudoWallItem> getRecentKudos(Integer numberOfRecords) {
    try {
      Integer recordLimit = numberOfRecords != null ? numberOfRecords : 20;
      List<Kudo__c> kudos = [
        SELECT
          Id,
          Message__c,
          CreatedDate,
          Recipient__c,
          Recipient__r.Name,
          Giver__r.Name,
          Badge_Type__r.Name,
          Badge_Type__r.Icon_Name__c
        FROM Kudo__c
        WITH USER_MODE
        ORDER BY CreatedDate DESC
        LIMIT :recordLimit
      ];

      Set<Id> recipientIds = new Set<Id>();
      for (Kudo__c k : kudos) {
        recipientIds.add(k.Recipient__c);
      }

      Map<Id, Decimal> pointsByUser = new Map<Id, Decimal>();
      for (Employee_Points__c ep : [
        SELECT User__c, Total_Points__c
        FROM Employee_Points__c
        WHERE User__c IN :recipientIds
        WITH USER_MODE
      ]) {
        pointsByUser.put(ep.User__c, ep.Total_Points__c);
      }

      List<KudoWallItem> items = new List<KudoWallItem>();
      for (Kudo__c k : kudos) {
        KudoWallItem item = new KudoWallItem();
        item.id = k.Id;
        item.message = k.Message__c;
        item.recipientName = k.Recipient__r != null
          ? k.Recipient__r.Name
          : null;
        item.giverName = k.Giver__r != null ? k.Giver__r.Name : null;
        item.badgeName = k.Badge_Type__r != null ? k.Badge_Type__r.Name : null;
        item.badgeIcon = k.Badge_Type__r != null
          ? k.Badge_Type__r.Icon_Name__c
          : null;

        Decimal points = pointsByUser.containsKey(k.Recipient__c)
          ? pointsByUser.get(k.Recipient__c)
          : 0;
        Points_Milestone__mdt tier = resolveTier(points);
        item.tierLabel = tier != null ? tier.Tier_Label__c : null;
        item.tierIcon = tier != null ? tier.Icon_Emoji__c : null;

        items.add(item);
      }
      return items;
    } catch (QueryException e) {
      throw wrapForClient('Unable to load the kudos wall right now.');
    }
  }

  private static Points_Milestone__mdt resolveTier(Decimal points) {
    Points_Milestone__mdt best;
    for (
      Points_Milestone__mdt milestone : Points_Milestone__mdt.getAll().values()
    ) {
      if (
        milestone.Minimum_Points__c <= points &&
        (best == null ||
        milestone.Minimum_Points__c > best.Minimum_Points__c)
      ) {
        best = milestone;
      }
    }
    return best;
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

  private static Integer getMaxKudosPerDay(Kudos_Settings__c settings) {
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
