@isTest
private class KudoTriggerHandlerTest {
    @TestSetup
    static void setup() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User giver = buildUser(p.Id, 'Giver', 'kbgiver');
        User recipient = buildUser(p.Id, 'Recipient', 'kbrecip');
        insert new List<User>{ giver, recipient };

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN ('Kudos_User', 'Kudos_Admin')]) {
            assignments.add(new PermissionSetAssignment(AssigneeId = giver.Id, PermissionSetId = ps.Id));
        }
        insert assignments;

        Kudos_Settings__c settings = Kudos_Settings__c.getOrgDefaults();
        settings.Max_Kudos_Per_Day__c = 300;
        upsert settings;
    }

    private static User buildUser(Id profileId, String lastName, String aliasVal) {
        return new User(
            FirstName = 'Test',
            LastName = lastName,
            Email = aliasVal + '@kudos.example.com',
            Username = aliasVal + System.currentTimeMillis() + '@kudos.example.com',
            Alias = aliasVal,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = profileId
        );
    }

    private static Badge_Type__c createBadge() {
        Badge_Type__c badge = new Badge_Type__c(
            Name = 'Innovator',
            Points_Value__c = 10,
            Active__c = true
        );
        insert badge;
        return badge;
    }

    @isTest
    static void testBulkInsertRollsUpPoints() {
        User giver = [SELECT Id FROM User WHERE LastName = 'Giver' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE LastName = 'Recipient' LIMIT 1];

        System.runAs(giver) {
            Badge_Type__c badge = createBadge();

            List<Kudo__c> kudos = new List<Kudo__c>();
            for (Integer i = 0; i < 50; i++) {
                kudos.add(new Kudo__c(
                    Recipient__c = recipient.Id,
                    Giver__c = giver.Id,
                    Badge_Type__c = badge.Id,
                    Message__c = 'Bulk kudo ' + i
                ));
            }

            Test.startTest();
            insert kudos;
            Test.stopTest();
        }

        Employee_Points__c points = [SELECT Total_Points__c FROM Employee_Points__c WHERE User__c = :recipient.Id];
        System.assertEquals(500, points.Total_Points__c, 'Points should sum across all bulk-inserted kudos');
    }

    @isTest
    static void testSecondBatchAddsToExistingPoints() {
        User giver = [SELECT Id FROM User WHERE LastName = 'Giver' LIMIT 1];
        User recipient = [SELECT Id FROM User WHERE LastName = 'Recipient' LIMIT 1];

        System.runAs(giver) {
            Badge_Type__c badge = createBadge();

            insert new Kudo__c(
                Recipient__c = recipient.Id,
                Giver__c = giver.Id,
                Badge_Type__c = badge.Id,
                Message__c = 'First batch'
            );

            Test.startTest();
            insert new Kudo__c(
                Recipient__c = recipient.Id,
                Giver__c = giver.Id,
                Badge_Type__c = badge.Id,
                Message__c = 'Second batch'
            );
            Test.stopTest();
        }

        Employee_Points__c points = [SELECT Total_Points__c FROM Employee_Points__c WHERE User__c = :recipient.Id];
        System.assertEquals(20, points.Total_Points__c, 'Second insert should add to the existing Employee_Points__c row');
    }
}