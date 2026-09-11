@isTest
private class KudosServiceTest {
  @TestSetup
  static void setup() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
    User giver = buildUser(p.Id, 'Giver', 'kgiver');
    User recipient = buildUser(p.Id, 'Recipient', 'krecip');
    insert new List<User>{ giver, recipient };

    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN ('Kudos_User', 'Kudos_Admin')
    ]) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = giver.Id,
          PermissionSetId = ps.Id
        )
      );
    }
    insert assignments;

    Kudos_Settings__c settings = Kudos_Settings__c.getOrgDefaults();
    settings.Max_Kudos_Per_Day__c = 2;
    settings.Enable_Leaderboard__c = true;
    settings.Notify_Recipient__c = true;
    upsert settings;
  }

  private static User buildUser(
    Id profileId,
    String lastName,
    String aliasVal
  ) {
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
      Name = 'Team Player',
      Points_Value__c = 10,
      Active__c = true
    );
    insert badge;
    return badge;
  }

  @isTest
  static void testGiveKudoSuccess() {
    User giver = [SELECT Id FROM User WHERE LastName = 'Giver' LIMIT 1];
    User recipient = [SELECT Id FROM User WHERE LastName = 'Recipient' LIMIT 1];
    Kudo__c kudo;

    System.runAs(giver) {
      Badge_Type__c badge = createBadge();
      Test.startTest();
      kudo = KudosService.giveKudo(recipient.Id, badge.Id, 'Great work!');
      Test.stopTest();
    }

    System.assertNotEquals(null, kudo.Id, 'Kudo should be inserted');

    Employee_Points__c points = [
      SELECT Total_Points__c
      FROM Employee_Points__c
      WHERE User__c = :recipient.Id
    ];
    System.assertEquals(
      10,
      points.Total_Points__c,
      'Points should roll up from badge value'
    );
  }

  @isTest
  static void testGiveKudoToSelfThrows() {
    User giver = [SELECT Id FROM User WHERE LastName = 'Giver' LIMIT 1];
    Boolean threw = false;

    System.runAs(giver) {
      Badge_Type__c badge = createBadge();
      try {
        KudosService.giveKudo(giver.Id, badge.Id, 'Nice!');
      } catch (AuraHandledException e) {
        threw = true;
        System.assertEquals(
          'You cannot give a kudo to yourself.',
          e.getMessage()
        );
      }
    }

    System.assert(threw, 'Should not allow giving a kudo to yourself');
  }

  @isTest
  static void testDailyLimitEnforced() {
    User giver = [SELECT Id FROM User WHERE LastName = 'Giver' LIMIT 1];
    User recipient = [SELECT Id FROM User WHERE LastName = 'Recipient' LIMIT 1];
    Boolean threw = false;

    System.runAs(giver) {
      Badge_Type__c badge = createBadge();
      KudosService.giveKudo(recipient.Id, badge.Id, 'One');
      KudosService.giveKudo(recipient.Id, badge.Id, 'Two');

      try {
        KudosService.giveKudo(recipient.Id, badge.Id, 'Three');
      } catch (AuraHandledException e) {
        threw = true;
        System.assertEquals(
          'You have reached your daily kudos limit of 2.',
          e.getMessage()
        );
      }
    }

    System.assert(threw, 'Should enforce max kudos per day limit of 2');
  }

  @isTest
  static void testMultipleKudosAccumulatePoints() {
    User giver = [SELECT Id FROM User WHERE LastName = 'Giver' LIMIT 1];
    User recipient = [SELECT Id FROM User WHERE LastName = 'Recipient' LIMIT 1];

    Kudos_Settings__c settings = Kudos_Settings__c.getOrgDefaults();
    settings.Max_Kudos_Per_Day__c = 5;
    upsert settings;

    System.runAs(giver) {
      Badge_Type__c badge = createBadge();
      KudosService.giveKudo(recipient.Id, badge.Id, 'First');
      KudosService.giveKudo(recipient.Id, badge.Id, 'Second');
    }

    Employee_Points__c points = [
      SELECT Total_Points__c
      FROM Employee_Points__c
      WHERE User__c = :recipient.Id
    ];
    System.assertEquals(
      20,
      points.Total_Points__c,
      'Points should accumulate across multiple kudos'
    );
  }

  @isTest
  static void testGetActiveBadgeTypesExcludesInactive() {
    insert new Badge_Type__c(
      Name = 'Active Badge',
      Points_Value__c = 5,
      Active__c = true
    );
    insert new Badge_Type__c(
      Name = 'Inactive Badge',
      Points_Value__c = 5,
      Active__c = false
    );

    User giver = [SELECT Id FROM User WHERE LastName = 'Giver' LIMIT 1];
    List<Badge_Type__c> results;
    System.runAs(giver) {
      Test.startTest();
      results = KudosService.getActiveBadgeTypes();
      Test.stopTest();
    }

    System.assertEquals(
      1,
      results.size(),
      'Only the active badge type should be returned'
    );
    System.assertEquals('Active Badge', results[0].Name);
  }

  @isTest
  static void testGetRecentKudosReturnsGivenKudo() {
    User giver = [SELECT Id FROM User WHERE LastName = 'Giver' LIMIT 1];
    User recipient = [SELECT Id FROM User WHERE LastName = 'Recipient' LIMIT 1];
    List<KudosService.KudoWallItem> results;

    System.runAs(giver) {
      Badge_Type__c badge = createBadge();
      KudosService.giveKudo(recipient.Id, badge.Id, 'Great teamwork!');

      Test.startTest();
      results = KudosService.getRecentKudos(10);
      Test.stopTest();
    }

    System.assertEquals(
      1,
      results.size(),
      'The kudo just given should appear in the recent list'
    );
    System.assertEquals('Great teamwork!', results[0].message);
    System.assertEquals(
      'Bronze',
      results[0].tierLabel,
      'A recipient with fewer than 50 points should resolve to the Bronze tier'
    );
  }

  @isTest
  static void testGetRecentKudosResolvesHigherTierAfterMorePoints() {
    User giver = [SELECT Id FROM User WHERE LastName = 'Giver' LIMIT 1];
    User recipient = [SELECT Id FROM User WHERE LastName = 'Recipient' LIMIT 1];
    List<KudosService.KudoWallItem> results;

    Kudos_Settings__c settings = Kudos_Settings__c.getOrgDefaults();
    settings.Max_Kudos_Per_Day__c = 10;
    upsert settings;

    System.runAs(giver) {
      Badge_Type__c badge = new Badge_Type__c(
        Name = 'Big Badge',
        Points_Value__c = 60,
        Active__c = true
      );
      insert badge;
      KudosService.giveKudo(recipient.Id, badge.Id, 'Huge win!');

      Test.startTest();
      results = KudosService.getRecentKudos(10);
      Test.stopTest();
    }

    System.assertEquals(
      'Silver',
      results[0].tierLabel,
      'A recipient with 60 points should resolve to the Silver tier'
    );
  }
}
