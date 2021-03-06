/********************************************************************************
 * Copyright (c) 2017, 2018 Bosch Connected Devices and Solutions GmbH.
 * 
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License 2.0 which is available at
 * http://www.eclipse.org/legal/epl-2.0.
 * 
 * Contributors:
 *    Bosch Connected Devices and Solutions GmbH - initial contribution
 * 
 * SPDX-License-Identifier: EPL-2.0
 ********************************************************************************/

/*
 * generated by Xtext 2.10.0
 */
package org.eclipse.mita.program.ui.quickfix

import com.google.inject.Inject
import org.eclipse.emf.ecore.EObject
import org.eclipse.mita.base.expressions.ExpressionsFactory
import org.eclipse.mita.base.expressions.ExpressionsPackage
import org.eclipse.mita.base.expressions.PrimitiveValueExpression
import org.eclipse.mita.base.types.EnumerationType
import org.eclipse.mita.base.types.PrimitiveType
import org.eclipse.mita.base.types.SumType
import org.eclipse.mita.base.types.Type
import org.eclipse.mita.base.types.TypesFactory
import org.eclipse.mita.base.types.typesystem.GenericTypeSystem
import org.eclipse.mita.base.types.typesystem.ITypeSystem
import org.eclipse.mita.base.ui.quickfix.TypeDslQuickfixProvider
import org.eclipse.mita.library.^extension.LibraryExtensions
import org.eclipse.mita.platform.AbstractSystemResource
import org.eclipse.mita.program.Program
import org.eclipse.mita.program.ProgramFactory
import org.eclipse.mita.program.ProgramPackage
import org.eclipse.mita.program.SystemResourceSetup
import org.eclipse.mita.program.validation.ProgramImportValidator
import org.eclipse.mita.program.validation.ProgramSetupValidator
import org.eclipse.xtext.scoping.IScopeProvider
import org.eclipse.xtext.scoping.impl.FilteringScope
import org.eclipse.xtext.ui.editor.quickfix.Fix
import org.eclipse.xtext.ui.editor.quickfix.IssueResolutionAcceptor
import org.eclipse.xtext.validation.Issue

class ProgramDslQuickfixProvider extends TypeDslQuickfixProvider {

	@Inject
	protected IScopeProvider scopeProvider;
	
	@Inject
	protected ITypeSystem typeSystem;

	@Fix(ProgramImportValidator.MISSING_TARGET_PLATFORM_CODE)
	def addMissingPlatform(Issue issue, IssueResolutionAcceptor acceptor) {
		LibraryExtensions.availablePlatforms.forEach [ platform |
			acceptor.accept(issue, '''Import '«platform.id»' '''.toString,
				'''Add import for platform '«platform.id»' '''.toString, '', [ element, context |
					val program = element as Program
					program.imports += TypesFactory.eINSTANCE.createImportStatement => [
						importedNamespace = platform.id
					]
				])
		]
	}

	@Fix(ProgramSetupValidator.MISSING_CONIGURATION_ITEM_CODE)
	def addMissingConfigItem(Issue issue, IssueResolutionAcceptor acceptor) {
		acceptor.accept(issue, 'Add config items', 'Add missing configuration items', '', [ element, context |

			val setup = element as SystemResourceSetup
			setup.type.configurationItems.filter[required] // item is mandatory
			.filter[!setup.configurationItemValues.map[c|c.item].contains(it)] // item is not contained in setup
			.forEach [ missingItem | // create dummy value
				val newConfigItemValue = ProgramFactory.eINSTANCE.createConfigurationItemValue
				setup.configurationItemValues.add(newConfigItemValue)
				newConfigItemValue.item = missingItem
				newConfigItemValue.value = missingItem.type.dummyExpression(newConfigItemValue)
			]
		])
	}

	protected def dispatch dummyExpression(Type itemType, EObject context) {
		// fall-back, just print a default text
		createDummyString
	}
	
	protected def dispatch dummyExpression(PrimitiveType itemType, EObject context) {
		if (typeSystem.isSuperType(itemType, typeSystem.getType(GenericTypeSystem.INTEGER))) {
			createDummyInteger
		} else if (typeSystem.isSuperType(itemType, typeSystem.getType(GenericTypeSystem.STRING))) {
			createDummyString
		} else if (typeSystem.isSuperType(itemType, typeSystem.getType(GenericTypeSystem.BOOLEAN))) {
			createDummyBool
		} else {
			createDummyString
		}
	}
	
	protected def PrimitiveValueExpression createDummyString() {
		return ExpressionsFactory.eINSTANCE.createPrimitiveValueExpression => [
			value = ExpressionsFactory.eINSTANCE.createStringLiteral => [
				value = 'replace_me'
			]
		]
	}
	
	protected def PrimitiveValueExpression createDummyInteger() {
		return ExpressionsFactory.eINSTANCE.createPrimitiveValueExpression => [
			value = ExpressionsFactory.eINSTANCE.createIntLiteral => [
				value = 0
			]
		]
	}
	
	protected def PrimitiveValueExpression createDummyBool() {
		return ExpressionsFactory.eINSTANCE.createPrimitiveValueExpression => [
			value = ExpressionsFactory.eINSTANCE.createBoolLiteral => [
				value = true
			]
		]
	}

	protected def dispatch dummyExpression(EnumerationType itemType, EObject context) {
		if (!itemType.enumerator.isEmpty) {
			return ExpressionsFactory.eINSTANCE.createElementReferenceExpression => [
				reference = itemType.enumerator.head
			]
		}
		return createDummyString
	}
	
	protected def dispatch dummyExpression(SumType itemType, EObject context) {
		if (!itemType.alternatives.isEmpty) {
			return ExpressionsFactory.eINSTANCE.createElementReferenceExpression => [
				reference = itemType.alternatives.head
			]
		}
		return createDummyString
	}

	protected def dispatch dummyExpression(AbstractSystemResource itemType, EObject context) {
		val scope = getSetupScope(itemType, context);
		if (!scope.allElements.empty) {
			return ExpressionsFactory.eINSTANCE.createElementReferenceExpression => [
				reference = scope.allElements.head.EObjectOrProxy
			]
		}
		return createDummyString
	}
	
	protected def FilteringScope getSetupScope(AbstractSystemResource itemType, EObject context) {
		new FilteringScope(
			scopeProvider.getScope(context, ExpressionsPackage.Literals.ELEMENT_REFERENCE_EXPRESSION__REFERENCE),
			[
				ProgramPackage.Literals.SYSTEM_RESOURCE_SETUP.isSuperTypeOf(it.EClass) &&
					(it.EObjectOrProxy as SystemResourceSetup).type == itemType
			]
		)
	}

}
