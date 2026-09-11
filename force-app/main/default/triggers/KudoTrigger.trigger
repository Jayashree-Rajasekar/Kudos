trigger KudoTrigger on Kudo__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        KudosTriggerHandler.afterInsert(Trigger.new);
    }
}