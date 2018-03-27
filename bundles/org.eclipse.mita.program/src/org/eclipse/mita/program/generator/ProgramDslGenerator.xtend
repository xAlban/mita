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
package org.eclipse.mita.program.generator

import com.google.inject.Guice
import com.google.inject.Inject
import com.google.inject.Injector
import com.google.inject.Module
import com.google.inject.Provider
import com.google.inject.name.Named
import com.google.inject.util.Modules
import java.util.LinkedList
import org.eclipse.core.resources.IFile
import org.eclipse.core.resources.IProject
import org.eclipse.core.resources.IWorkspaceRoot
import org.eclipse.core.resources.ResourcesPlugin
import org.eclipse.core.runtime.Path
import org.eclipse.emf.common.util.URI
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.emf.ecore.resource.ResourceSet
import org.eclipse.mita.platform.AbstractSystemResource
import org.eclipse.mita.program.Program
import org.eclipse.mita.program.SystemResourceSetup
import org.eclipse.mita.program.generator.internal.EntryPointGenerator
import org.eclipse.mita.program.generator.internal.ExceptionGenerator
import org.eclipse.mita.program.generator.internal.GeneratedTypeGenerator
import org.eclipse.mita.program.generator.internal.IGeneratorOnResourceSet
import org.eclipse.mita.program.generator.internal.ProgramCopier
import org.eclipse.mita.program.generator.internal.SystemResourceHandlingGenerator
import org.eclipse.mita.program.generator.internal.TimeEventGenerator
import org.eclipse.mita.program.generator.internal.UserCodeFileGenerator
import org.eclipse.mita.program.generator.transformation.ProgramGenerationTransformationPipeline
import org.eclipse.mita.types.scoping.TypesLibraryProvider
import org.eclipse.xtext.generator.AbstractGenerator
import org.eclipse.xtext.generator.IFileSystemAccess2
import org.eclipse.xtext.generator.IGeneratorContext
import org.eclipse.xtext.generator.trace.node.CompositeGeneratorNode
import org.eclipse.xtext.service.DefaultRuntimeModule

/**
 * Generates code from your model files on save.
 * 
 * See https://www.eclipse.org/Xtext/documentation/303_runtime_concepts.html#code-generation
 */
class ProgramDslGenerator extends AbstractGenerator implements IGeneratorOnResourceSet {

	@Inject 
	protected extension ProgramDslTraceExtensions
	
	@Inject
	protected extension ProgramCopier
	
	@Inject
	protected Provider<ProgramGenerationTransformationPipeline> transformer
	
	@Inject
	protected extension GeneratorUtils
	
	@Inject(optional=true)
	protected IPlatformMakefileGenerator makefileGenerator

	@Inject
	protected EntryPointGenerator entryPointGenerator
	
	@Inject
	protected ExceptionGenerator exceptionGenerator
	
	@Inject
	protected GeneratedTypeGenerator generatedTypeGenerator
	
	@Inject
	protected TimeEventGenerator timeEventGenerator
	
	@Inject
	protected SystemResourceHandlingGenerator systemResourceGenerator
	
	@Inject
	protected UserCodeFileGenerator userCodeGenerator
	
	@Inject 
	protected Injector injector
	
	@Inject 
	protected TypesLibraryProvider libraryProvider
	
	@Inject @Named("injectingModule")
	protected DefaultRuntimeModule injectingModule
	
	@Inject
	protected CompilationContextProvider compilationContextProvider;

	override void doGenerate(Resource resource, IFileSystemAccess2 fsa, IGeneratorContext context) {
		resource.resourceSet.doGenerate(fsa);
	}
	
	protected def getLibraryModule(Resource resource) {
		val libraryModule = libraryProvider.getImportedLibraries(resource).
			map[module].
			filterNull.
			reduce[module1, module2 | Modules.override(module1).with(module2)]
			if(libraryModule === null)
				return new EmptyPlatformGeneratorModule();
			libraryModule
	}
	
	protected def isMainApplicationFile(Resource resource) {
		return resource.URI.segments.last.startsWith('application.')
	}
	
	protected def injectPlatformDependencies(Module libraryModule) {
		injector = Guice.createInjector(injectingModule, libraryModule);
		injector.injectMembers(this)
	}

	private def produceFile(IFileSystemAccess2 fsa, String path, EObject ctx, CompositeGeneratorNode content) {
		var root = CodeFragment.cleanNullChildren(content);
		fsa.generateTracedFile(path, root);
		return path
	}
	
	override doGenerate(ResourceSet input, IFileSystemAccess2 fsa) {
		val resourcesToCompile = input
			.resources
			.filter[x | x.URI?.segment(0) == 'resource' ]
			.toList();
		
		// Include libraries such as the stdlib in the compilation context
		val libs = libraryProvider.getLibraries(resourcesToCompile.head);
		val stdlibUri = libs.filter[it.toString.endsWith(".mita")]
		val stdlib = stdlibUri.map[input.getResource(it, true).contents.filter(Program).head]

		injectPlatformDependencies(resourcesToCompile.get(0).libraryModule);
		
		/*
		 * Steps:
		 *  1. Copy all programs
		 *  2. Run all programs through pipeline
		 *  3. Collect all sensors, connectivity, exceptions, types
		 *  4. Generate shared files
		 *  5. Generate user code per input model file
		 */
		val compilationUnits = (resourcesToCompile)
			.map[x | x.contents.filter(Program).head ]
			.filterNull
			.map[x | transformer.get.transform(x.copy) ]
			.toList();
		
		val someProgram = compilationUnits.head;
		val context = compilationContextProvider.get(compilationUnits, stdlib);
		
		val files = new LinkedList<String>();
		val userTypeFiles = new LinkedList<String>();
		
		
		// generate all the infrastructure bits
		files += fsa.produceFile('main.c', someProgram, entryPointGenerator.generateMain(context));
		files += fsa.produceFile('base/MitaEvents.h', someProgram, entryPointGenerator.generateEventHeader(context));
		files += fsa.produceFile('base/MitaExceptions.h', someProgram, exceptionGenerator.generateHeader(context));
		
		if (context.hasTimeEvents) {
			files += fsa.produceFile('base/MitaTime.h', someProgram, timeEventGenerator.generateHeader(context));
			files += fsa.produceFile('base/MitaTime.c', someProgram, timeEventGenerator.generateImplementation(context));
		}
		
		for (resourceOrSetup : context.getResourceGraph().nodes.filter(EObject)) {
			if(resourceOrSetup instanceof AbstractSystemResource
			|| resourceOrSetup instanceof SystemResourceSetup) { 
				files += fsa.produceFile('''base/«resourceOrSetup.fileBasename».h''', resourceOrSetup as EObject, systemResourceGenerator.generateHeader(context, resourceOrSetup));
				files += fsa.produceFile('''base/«resourceOrSetup.fileBasename».c''', resourceOrSetup as EObject, systemResourceGenerator.generateImplementation(context, resourceOrSetup));
			}
		}
	
		for (program : compilationUnits.filter[x | 
			!x.eventHandlers.empty || !x.functionDefinitions.empty || !x.types.empty
		]) {
			// generate the actual content for this resource
			files += fsa.produceFile(userCodeGenerator.getResourceBaseName(program) + '.c', program, stdlib.head.trace.append(userCodeGenerator.generateImplementation(context, program)));
			files += fsa.produceFile(userCodeGenerator.getResourceBaseName(program) + '.h', program, stdlib.head.trace.append(userCodeGenerator.generateHeader(context, program)));
			val compilationUnitTypesFilename = userCodeGenerator.getResourceTypesName(program) + '.h';
			files += fsa.produceFile(compilationUnitTypesFilename, program, stdlib.head.trace.append(userCodeGenerator.generateTypes(context, program)));
			userTypeFiles += compilationUnitTypesFilename;
		}
		
		files += fsa.produceFile('base/MitaGeneratedTypes.h', someProgram, generatedTypeGenerator.generateHeader(context, userTypeFiles));
		
		files += getUserFiles(input);
		
		val codefragment = makefileGenerator?.generateMakefile(null, files)
		if(codefragment !== null && codefragment != CodeFragment.EMPTY)
			fsa.produceFile('Makefile', someProgram, codefragment);
	}
		
	def Iterable<String> getUserFiles(ResourceSet set) {
        val resource = set.resources.head;   
        val URI uri = resource.URI;
        val projectName = new Path(uri.toPlatformString(true)).segment(0);
        
        val IWorkspaceRoot workspaceRoot = ResourcesPlugin.getWorkspace().getRoot();
        val IProject project = workspaceRoot.getProject(projectName);
        return project
            .members()
            .filter(IFile)
            .map[ it.fullPath.lastSegment ]
            .filter[ it.endsWith(".c") ]
            .map[ "../" + it ];
    }
	
}