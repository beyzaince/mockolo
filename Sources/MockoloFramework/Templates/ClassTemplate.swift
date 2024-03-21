//
//  Copyright (c) 2018. Uber Technologies
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

extension ClassModel {
    private func createUniqueId(model: MethodModel, uniqueId: String, uniqueIds: [String]) -> String {
        var _uniqueId: String = uniqueId
        var index = 0
        let params = model.params
        while uniqueIds.contains(_uniqueId) {
            if params.count > index {
                let param = params[index]
                _uniqueId = _uniqueId + param.name.capitalizeFirstLetter
            } else {
                _uniqueId = _uniqueId + String(index)
            }
            index = index + 1
        }
        return _uniqueId
    }

    func applyClassTemplate(name: String,
                            identifier: String,
                            accessLevel: String,
                            attribute: String,
                            declType: DeclType,
                            metadata: AnnotationMetadata?,
                            useTemplateFunc: Bool,
                            useMockObservable: Bool,
                            allowSetCallCount: Bool,
                            mockFinal: Bool,
                            enableFuncArgsHistory: Bool,
                            disableCombineDefaultValues: Bool,
                            initParamCandidates: [Model],
                            declaredInits: [MethodModel],
                            entities: [(String, Model)]) -> String {

        processCombineAliases(entities: entities)
        
        let acl = accessLevel.isEmpty ? "" : accessLevel + " "
        let typealiases = typealiasWhitelist(in: entities)
        var enumElements = """
                           """
        var uniqueIds: [String] = []
        let renderedEntities = entities
            .compactMap { (uniqueId: String, model: Model) -> (String, Int64)? in
                if model.name.contains("MockIdentifier") {
                    return nil
                }
                if model.name.contains("invokedList") {
                    return nil
                }
                if model.modelType == .typeAlias, let _ = typealiases?[model.name] {
                    // this case will be handlded by typealiasWhitelist look up later
                    return nil
                }
                if model.modelType == .variable, model.name == String.hasBlankInit {
                    return nil
                }
                if model.modelType == .method, model.isInitializer, !model.processed {
                    return nil
                }
                if let ret = model.render(with: uniqueId, encloser: name, useTemplateFunc: useTemplateFunc, useMockObservable: useMockObservable, allowSetCallCount: allowSetCallCount, mockFinal: mockFinal, enableFuncArgsHistory: enableFuncArgsHistory, disableCombineDefaultValues: disableCombineDefaultValues) {
                    var _ret = ret
                    if let variableModel = model as? VariableModel {
                        if !variableModel.name.contains("stubbed") {
                            let ifSetterExists = (variableModel.modelDescription?.contains("get set") ?? false ||
                                                  variableModel.modelDescription?.contains("set get") ?? false ||
                                                  variableModel.modelDescription?.contains("set {") ?? false
                            )
                            if ifSetterExists {
                                enumElements += "\n\(1.tab)case \(uniqueId)Setter(value: \(variableModel.type.typeName))"
                            }
                            enumElements += "\n\(1.tab)case \(uniqueId)Getter"
                            uniqueIds.append(uniqueId)
                        }
                    }
                    if let methodModel = model as? MethodModel {
                        var _uniqueId = uniqueId

                        if !methodModel.params.isEmpty {
                            if methodModel.processed,
                               let modelDesc = methodModel.modelDescription {
                                _uniqueId = modelDesc.slice(from: "append(.", to: "(") ?? uniqueId
                            }
                            let params = methodModel.params.map{ $0.name + ": " + $0.type.typeName.replacingOccurrences(of: "@escaping", with: "") }.joined(separator: ", ")
                            if !uniqueIds.contains(_uniqueId) {
                                enumElements += "\n\(1.tab)case \(_uniqueId)(\(params))"
                            } else {
                                _uniqueId = createUniqueId(model: methodModel, uniqueId: uniqueId, uniqueIds: uniqueIds)
                                _ret = _ret.replacingOccurrences(of: "append(.\(uniqueId)", with: "append(.\(_uniqueId)")
                                enumElements += "\n\(1.tab)case \(_uniqueId)(\(params))"
                            }
                            uniqueIds.append(_uniqueId)
                        } else {
                            if methodModel.processed,
                               let modelDesc =  methodModel.modelDescription {
                                _uniqueId = modelDesc.slice(from: "append(.", to: ")") ?? uniqueId
                                if !uniqueIds.contains(_uniqueId) {
                                    enumElements += "\n\(1.tab)case \(_uniqueId)"
                                } else {
                                    _uniqueId = createUniqueId(model: methodModel, uniqueId: uniqueId, uniqueIds: uniqueIds)
                                    _ret = _ret.replacingOccurrences(of: "append(.\(uniqueId)", with: "append(.\(_uniqueId)")
                                    enumElements += "\n\(1.tab)case \(_uniqueId)"
                                }
                            } else {
                                enumElements += "\n\(1.tab)case \(_uniqueId)"
                            }
                            uniqueIds.append(_uniqueId)
                        }
                    }
                    return (_ret, model.offset)
                }
                return nil
        }
        .sorted { (left: (String, Int64), right: (String, Int64)) -> Bool in
            if left.1 == right.1 {
                return left.0 < right.0
            }
            return left.1 < right.1
        }
        .map {$0.0}
        .joined(separator: "\n")
        
        var moduleDot = ""
        if let moduleName = metadata?.module, !moduleName.isEmpty {
            moduleDot = moduleName + "."
        }
        
        let extraInits = extraInitsIfNeeded(initParamCandidates: initParamCandidates, declaredInits: declaredInits,  acl: acl, declType: declType, overrides: metadata?.varTypes)

        var body = ""
        if !extraInits.isEmpty {
            body += "\(extraInits)"
        }
        if !renderedEntities.isEmpty {
            body += "\(renderedEntities)"
        }

        body = body.replacingOccurrences(of: "}\n    ", with: "}\n\n    ")

        var template = """
        \(acl)final class \(name): \(moduleDot)\(identifier), MockAssertable {
        """

        template = """
        \(template)
        \(1.tab)\(acl)typealias MockIdentifier = \(name)Elements
        \(1.tab)\(acl)var invokedList: [\(name)Elements] = []
        """

        template = """
        \(template)
        \(attribute)
        \(body)
        }
        """

        template = """
        \(template)
        \(acl)enum \(name)Elements: MockEquatable {
        \(1.tab)\(enumElements)
        }
        """

        template = template.replacingOccurrences(of: "\n}\nenum", with: "\n}\n\nenum")
        template = template.replacingOccurrences(of: "MockEquatable {\n    \n", with: "MockEquatable {\n")
        
        return template
    }
    
    private func extraInitsIfNeeded(initParamCandidates: [Model],
                                    declaredInits: [MethodModel],
                                    acl: String,
                                    declType: DeclType,
                                    overrides: [String: String]?) -> String {
        
        let declaredInitParamsPerInit = declaredInits.map { $0.params }
        
        var needParamedInit = false
        var needBlankInit = false
        
        if declaredInits.isEmpty, initParamCandidates.isEmpty {
            needBlankInit = true
            needParamedInit = false
        } else {
            if declType == .protocolType {
                needParamedInit = !initParamCandidates.isEmpty
                needBlankInit = true

                let buffer = initParamCandidates.sorted(path: \.fullName, fallback: \.name)
                for paramList in declaredInitParamsPerInit {
                    if paramList.isEmpty {
                        needBlankInit = false
                    } else {
                        let list = paramList.sorted(path: \.fullName, fallback: \.name)
                        if list.count > 0, list.count == buffer.count {
                            let dups = zip(list, buffer).filter {$0.0.fullName == $0.1.fullName}
                            if !dups.isEmpty {
                                needParamedInit = false
                            }
                        }
                    }
                }
            }
        }
        
        var initTemplate = ""

        let extraInitParamNames = initParamCandidates.map{$0.name}
        let extraVarsToDecl = declaredInitParamsPerInit.flatMap{$0}.compactMap { (p: ParamModel) -> String? in
            if !extraInitParamNames.contains(p.name) {
                return p.asVarDecl
            }
            return nil
        }
        .joined(separator: "\n")

        let declaredInitStr = declaredInits.compactMap { (m: MethodModel) -> String? in
            if case let .initKind(required, override) = m.kind, !m.processed {
                let modifier = required ? "\(String.required) " : (override ? "\(String.override) " : "")
                let mAcl = m.accessLevel.isEmpty ? "" : "\(m.accessLevel) "
                let genericTypeDeclsStr = m.genericTypeParams.compactMap {$0.render(with: "", encloser: "")}.joined(separator: ", ")
                let genericTypesStr = genericTypeDeclsStr.isEmpty ? "" : "<\(genericTypeDeclsStr)>"
                let paramDeclsStr = m.params.compactMap{$0.render(with: "", encloser: "")}.joined(separator: ", ")

                if override {
                    let paramsList = m.params.map { param in
                        return "\(param.name): \(param.name.safeName)"
                    }.joined(separator: ", ")

                    return """
                    \(1.tab)\(modifier)\(mAcl)init\(genericTypesStr)(\(paramDeclsStr)) {
                    \(2.tab)super.init(\(paramsList))
                    \(1.tab)}
                    """
                } else {
                    let paramsAssign = m.params.map { param in
                        let underVars = initParamCandidates.compactMap { return $0.name.safeName == param.name.safeName ? $0.underlyingName : nil}
                        if let underVar = underVars.first {
                            return "\(2.tab)self.\(underVar) = \(param.name.safeName)"
                        } else {
                            return "\(2.tab)self.\(param.underlyingName) = \(param.name.safeName)"
                        }
                    }.joined(separator: "\n")

                    return """
                    \(1.tab)\(modifier)\(mAcl)init\(genericTypesStr)(\(paramDeclsStr)) {
                    \(paramsAssign)
                    \(1.tab)}
                    """
                }
            }
            return nil
        }.sorted().joined(separator: "\n")

        var template = ""

        if !extraVarsToDecl.isEmpty {
            template += "\(1.tab)\(extraVarsToDecl)\n"
        }

        if needBlankInit {
            // In case of protocol mocking, we want to provide a blank init (if not present already) for convenience,
            // where instance vars do not have to be set in init since they all have get/set (see VariableTemplate).
            let blankInit = "\(acl)init() { }"
            template += "\(1.tab)\(blankInit)\n"
        }

        if !initTemplate.isEmpty {
            template += "\(initTemplate)\n"
        }

        if !declaredInitStr.isEmpty {
            template += "\(declaredInitStr)\n"
        }

        return template
    }
    
    
    /// Returns a map of typealiases with conflicting types to be whitelisted
    /// @param models Potentially contains typealias models
    /// @returns A map of typealiases with multiple possible types
    func typealiasWhitelist(`in` models: [(String, Model)]) -> [String: [String]]? {
        let typealiasModels = models.filter{$0.1.modelType == .typeAlias}
        var aliasMap = [String: [String]]()
        typealiasModels.forEach { (arg: (key: String, value: Model)) in
            
            let alias = arg.value
            if aliasMap[alias.name] == nil {
                aliasMap[alias.name] = [alias.type.typeName]
            } else {
                if let val = aliasMap[alias.name], !val.contains(alias.type.typeName) {
                    aliasMap[alias.name]?.append(alias.type.typeName)
                }
            }
        }
        let aliasDupes = aliasMap.filter {$0.value.count > 1}
        return aliasDupes.isEmpty ? nil : aliasDupes
    }

    // Finds all combine properties that are attempting to use a property wrapper alias
    // and locates the matching property within the class, if one exists.
    //
    private func processCombineAliases(entities: [(String, Model)]) {
        var variableModels = [VariableModel]()
        var nameToVariableModels = [String: VariableModel]()

        for entity in entities {
            guard let variableModel = entity.1 as? VariableModel else {
                continue
            }
            variableModels.append(variableModel)
            nameToVariableModels[variableModel.name] = variableModel
        }

        for variableModel in variableModels {
            guard case .property(let wrapper, let name) = variableModel.combineType else {
                continue
            }

            // If a variable member in this entity already exists, link the two together.
            // Otherwise, the user's setup is incorrect and we will fallback to using a PassthroughSubject.
            //
            if let matchingAliasModel = nameToVariableModels[name] {
                variableModel.wrapperAliasModel = matchingAliasModel
                matchingAliasModel.propertyWrapper = wrapper
            } else {
                variableModel.combineType = .passthroughSubject
            }
        }
    }
}

extension String {

    func slice(from: String, to: String) -> String? {
        return (range(of: from)?.upperBound).flatMap { substringFrom in
            (range(of: to, range: substringFrom..<endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom..<substringTo])
            }
        }
    }
}
