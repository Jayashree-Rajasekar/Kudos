public with sharing class KudosService {
    public class KudosLimitException extends Exception {}

    @AuraEnabled
    public static Kudo__c giveKudo(Id recipientId, Id badgeTypeId, String message) {
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
            throw new KudosLimitException('You have reached your daily kudos limit of ' + maxPerDay + '.');
        }

        Kudo__c kudo = new Kudo__c(
            Recipient__c = recipientId,
            Giver__c = giverId,
            Badge_Type__c = badgeTypeId,
            Message__c = message
        );
        Database.insert(kudo, AccessLevel.USER_MODE);
        return kudo;
    }

    private static Integer getMaxKudosPerDay() {
        Kudos_Settings__c settings = Kudos_Settings__c.getInstance();
        return settings.Max_Kudos_Per_Day__c != null
            ? Integer.valueOf(settings.Max_Kudos_Per_Day__c)
            : 5;
    }
}