public with sharing class KudosTriggerHandler {
    public static void afterInsert(List<Kudo__c> newKudos) {
        Set<Id> recipientIds = new Set<Id>();
        Set<Id> badgeTypeIds = new Set<Id>();
        for (Kudo__c k : newKudos) {
            recipientIds.add(k.Recipient__c);
            if (k.Badge_Type__c != null) {
                badgeTypeIds.add(k.Badge_Type__c);
            }
        }

        Map<Id, Decimal> pointsByBadgeType = new Map<Id, Decimal>();
        for (Badge_Type__c bt : [SELECT Id, Points_Value__c FROM Badge_Type__c WHERE Id IN :badgeTypeIds]) {
            pointsByBadgeType.put(bt.Id, bt.Points_Value__c);
        }

        Map<Id, Decimal> pointsToAddByUser = new Map<Id, Decimal>();
        for (Kudo__c k : newKudos) {
            Decimal points = pointsByBadgeType.containsKey(k.Badge_Type__c) ? pointsByBadgeType.get(k.Badge_Type__c) : 0;
            Decimal existing = pointsToAddByUser.containsKey(k.Recipient__c) ? pointsToAddByUser.get(k.Recipient__c) : 0;
            pointsToAddByUser.put(k.Recipient__c, existing + points);
        }

        Map<Id, Employee_Points__c> existingByUser = new Map<Id, Employee_Points__c>();
        for (Employee_Points__c ep : [SELECT Id, User__c, Total_Points__c FROM Employee_Points__c WHERE User__c IN :recipientIds]) {
            existingByUser.put(ep.User__c, ep);
        }

        List<Employee_Points__c> toUpsert = new List<Employee_Points__c>();
        for (Id userId : pointsToAddByUser.keySet()) {
            Decimal pointsToAdd = pointsToAddByUser.get(userId);
            if (existingByUser.containsKey(userId)) {
                Employee_Points__c ep = existingByUser.get(userId);
                ep.Total_Points__c = (ep.Total_Points__c != null ? ep.Total_Points__c : 0) + pointsToAdd;
                toUpsert.add(ep);
            } else {
                toUpsert.add(new Employee_Points__c(
                    User__c = userId,
                    Total_Points__c = pointsToAdd
                ));
            }
        }

        if (!toUpsert.isEmpty()) {
            // Employee_Points__c is a system-maintained rollup; end users are never
            // granted direct write access to it, so this upsert runs in system mode.
            Database.upsert(toUpsert, AccessLevel.SYSTEM_MODE);
        }
    }
}