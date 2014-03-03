//
//  EMKManagedObjectDeserializer.m
//  EasyMappingCoreDataExample
//
//  Created by Lucas Medeiros on 2/24/14.
//  Copyright (c) 2014 EasyKit. All rights reserved.
//

#import "EMKManagedObjectDeserializer.h"

#import <CoreData/CoreData.h>

#import "EMKManagedObjectMapping.h"
#import "EMKAttributeMapping.h"
#import "EMKPropertyHelper.h"

#import "NSArray+EMKExtension.h"
#import "NSDictionary+EMKFieldMapping.h"
#import "EMKAttributeMapping+Extension.h"
#import "EMKRelationshipMapping.h"

@implementation EMKManagedObjectDeserializer

+ (id)getExistingObjectFromRepresentation:(id)representation withMapping:(EMKManagedObjectMapping *)mapping inManagedObjectContext:(NSManagedObjectContext *)moc {
	EMKAttributeMapping *primaryKeyFieldMapping = [mapping primaryKeyMapping];
	id primaryKeyValue = [primaryKeyFieldMapping mapValue:[representation valueForKeyPath:primaryKeyFieldMapping.keyPath]];

//	id primaryKeyValue = [self getValueOfField:primaryKeyFieldMapping fromRepresentation:externalRepresentation];
	if (!primaryKeyValue || primaryKeyValue == (id) [NSNull null]) {
			return nil;
	}

	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:mapping.entityName];
	[request setPredicate:[NSPredicate predicateWithFormat:@"%K = %@", mapping.primaryKey, primaryKeyValue]];

	NSArray *array = [moc executeFetchRequest:request error:NULL];
	if (array.count == 0) {
			return nil;
	}

	return [array lastObject];
}

+ (id)deserializeObjectRepresentation:(NSDictionary *)representation usingMapping:(EMKManagedObjectMapping *)mapping context:(NSManagedObjectContext *)context {
	NSManagedObject *object = [self getExistingObjectFromRepresentation:representation
	                                                        withMapping:mapping
			                                     inManagedObjectContext:context];
	if (!object) {
			object = [NSEntityDescription insertNewObjectForEntityForName:mapping.entityName
			                                       inManagedObjectContext:context];
	}
	return [self fillObject:object fromRepresentation:representation usingMapping:mapping];
}

+ (id)deserializeObjectExternalRepresentation:(NSDictionary *)externalRepresentation
                                 usingMapping:(EMKManagedObjectMapping *)mapping
			                          context:(NSManagedObjectContext *)context {
	id objectRepresentation = [mapping mappedExternalRepresentation:externalRepresentation];
	return [self deserializeObjectRepresentation:objectRepresentation usingMapping:mapping context:context];
}

+ (id)fillObject:(NSManagedObject *)object fromRepresentation:(NSDictionary *)representation usingMapping:(EMKManagedObjectMapping *)mapping {
	for (EMKAttributeMapping *attributeMapping in mapping.attributeMappings) {
		[attributeMapping mapValueToObject:object fromRepresentation:representation];
	}

	NSManagedObjectContext *context = object.managedObjectContext;
	for (EMKRelationshipMapping *relationshipMapping in mapping.relationshipMappings) {
		id deserializedRelationship = nil;

		if (relationshipMapping.isToMany) {
			deserializedRelationship = [self deserializeCollectionExternalRepresentation:representation
			                                                                usingMapping:relationshipMapping.objectMapping
						                                                         context:context];

			objc_property_t property = class_getProperty([object class], [relationshipMapping.property UTF8String]);
			deserializedRelationship = [deserializedRelationship ek_propertyRepresentation:property];
		} else {
			deserializedRelationship = [self deserializeObjectExternalRepresentation:representation
			                                                            usingMapping:relationshipMapping.objectMapping
						                                                     context:context];
		}

		if (deserializedRelationship) {
			[object setValue:deserializedRelationship forKey:relationshipMapping.property];
		}
	}

	return object;
}

+ (id)fillObject:(NSManagedObject *)object fromExternalRepresentation:(NSDictionary *)externalRepresentation usingMapping:(EMKManagedObjectMapping *)mapping {
	id objectRepresentation = [mapping mappedExternalRepresentation:externalRepresentation];
	return [self fillObject:object fromRepresentation:objectRepresentation usingMapping:mapping];
}

+ (NSArray *)deserializeCollectionRepresentation:(NSArray *)representation
                                    usingMapping:(EMKManagedObjectMapping *)mapping
			                             context:(NSManagedObjectContext *)context {
	NSMutableArray *array = [NSMutableArray array];
	for (id objectRepresentation in representation) {
		[array addObject:[self deserializeObjectRepresentation:objectRepresentation usingMapping:mapping context:context]];
	}
	return [NSArray arrayWithArray:array];
}

+ (NSArray *)deserializeCollectionExternalRepresentation:(NSArray *)externalRepresentation
                                            usingMapping:(EMKManagedObjectMapping *)mapping
			                                     context:(NSManagedObjectContext *)context {
	id representation = [mapping mappedExternalRepresentation:externalRepresentation];
	return [self deserializeCollectionRepresentation:representation usingMapping:mapping context:context];
}

+ (NSArray *)syncArrayOfObjectsFromExternalRepresentation:(NSArray *)externalRepresentation
                                              withMapping:(EMKManagedObjectMapping *)mapping
		                                     fetchRequest:(NSFetchRequest *)fetchRequest
					               inManagedObjectContext:(NSManagedObjectContext *)moc {
	NSAssert(mapping.primaryKey, @"A objectMapping with a primary key is required");
	EMKAttributeMapping *primaryKeyFieldMapping = [mapping primaryKeyMapping];

	// Create a dictionary that maps primary keys to existing objects
	NSArray *existing = [moc executeFetchRequest:fetchRequest error:NULL];
	NSDictionary *existingByPK = [NSDictionary dictionaryWithObjects:existing
	                                                         forKeys:[existing valueForKey:primaryKeyFieldMapping.property]];

	NSMutableArray *array = [NSMutableArray array];
	for (NSDictionary *representation in externalRepresentation) {
		// Look up the object by its primary key

		id primaryKeyValue = [primaryKeyFieldMapping mapValue:[externalRepresentation valueForKeyPath:primaryKeyFieldMapping.keyPath]];
		id object = [existingByPK objectForKey:primaryKeyValue];

		// Create a new object if necessary
		if (!object) {
					object = [NSEntityDescription insertNewObjectForEntityForName:mapping.entityName
					                                       inManagedObjectContext:moc];
		}

		[self fillObject:object fromExternalRepresentation:representation usingMapping:mapping];
		[array addObject:object];
	}

	// Any object returned by the fetch request not in the external represntation has to be deleted
	NSMutableSet *toDelete = [NSMutableSet setWithArray:existing];
	[toDelete minusSet:[NSSet setWithArray:array]];
	for (NSManagedObject *o in toDelete) {
			[moc deleteObject:o];
	}

	return [NSArray arrayWithArray:array];
}

@end