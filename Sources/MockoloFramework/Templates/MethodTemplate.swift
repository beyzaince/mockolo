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

extension MethodModel {
    func applyMethodTemplate(name: String,
                             identifier: String,
                             kind: MethodKind,
                             useTemplateFunc: Bool,
                             allowSetCallCount: Bool,
                             enableFuncArgsHistory: Bool,
                             isStatic: Bool,
                             customModifiers: [String: Modifier]?,
                             isOverride: Bool,
                             genericTypeParams: [ParamModel],
                             genericWhereClause: String?,
                             params: [ParamModel],
                             returnType: Type,
                             accessLevel: String,
                             suffix: String,
                             argsHistory: ArgumentsHistoryModel?,
                             handler: ClosureModel?) -> String {
        var template = ""

        let returnTypeName = returnType.isUnknown ? "" : returnType.typeName

        let acl = accessLevel.isEmpty ? "" : accessLevel+" "
        let genericTypeDeclsStr = genericTypeParams.compactMap {$0.render(with: "", encloser: "")}.joined(separator: ", ")
        let genericTypesStr = genericTypeDeclsStr.isEmpty ? "" : "<\(genericTypeDeclsStr)>"
        var genericWhereStr = ""
        if let clause = genericWhereClause {
            genericWhereStr = " \(clause)"
        }
        let paramDeclsStr = params.compactMap{$0.render(with: "", encloser: "")}.joined(separator: ", ")

        switch kind {
        case .initKind(_, _):  // ClassTemplate needs to handle this as it needs a context of all the vars
            return ""
        default:

            guard let handler = handler else { return "" }

            let callCount = "\(identifier)\(String.callCountSuffix)"
            let handlerVarName = "\(identifier)\(String.handlerSuffix)"
            let handlerVarType = handler.type.typeName // ?? "Any"

            let suffixStr = suffix.isEmpty ? "" : "\(suffix) "
            let returnStr = returnTypeName.isEmpty ? "" : "-> \(returnTypeName)"
            let staticStr = isStatic ? String.static + " " : ""
            let keyword = isSubscript ? "" : "func "
            var body = ""

            if useTemplateFunc {
                let callMockFunc = !suffix.hasThrowsOrRethrows && (handler.type.cast?.isEmpty ?? false)
                if callMockFunc {
                    let handlerParamValsStr = params.map { (arg) -> String in
                        if arg.type.typeName.hasPrefix(String.autoclosure) {
                            return arg.name.safeName + "()"
                        }
                        return arg.name.safeName
                    }.joined(separator: ", ")

                    let defaultVal = type.defaultVal() // ?? "nil"

                    var mockReturn = ".error"
                    if returnType.typeName.isEmpty {
                        mockReturn = ".void"
                    } else if let val = defaultVal {
                        mockReturn = ".val(\(val))"
                    }

                    body = """
                    \(2.tab)mockFunc(&\(callCount))(\"\(name)\", \(handlerVarName)?(\(handlerParamValsStr)), \(mockReturn))
                    """
                }
            }

            if body.isEmpty {
                if let argsHistory = argsHistory, argsHistory.enable(force: enableFuncArgsHistory) {
                    let argsHistoryCapture = argsHistory.render(with: identifier, encloser: "", enableFuncArgsHistory: enableFuncArgsHistory) ?? ""

                    body = """
                    \(body)
                    \(2.tab)\(argsHistoryCapture)
                    """
                }
            }

            var wrapped = body
            if isSubscript {
                wrapped = """
                \(2.tab)get {
                \(body)
                \(2.tab)}
                \(2.tab)set { }
                """
            }

            let overrideStr = isOverride ? "\(String.override) " : ""
            let modifierTypeStr: String
            if let customModifiers = customModifiers,
               let customModifier: Modifier = customModifiers[name] {
                modifierTypeStr = customModifier.rawValue + " "
            } else {
                modifierTypeStr = ""
            }
            
            if !returnType.isUnknown {
                if params.isEmpty {
                    template = """
                    \(template)
                    \(1.tab)var stubbed\(name.capitalizeFirstLetter)Result: \(returnTypeName)!
                    \(1.tab)\n
                    """
                } else {
                    let paramsInputs = params.map{$0.name.capitalizeFirstLetter}.joined(separator: "")
                    template = """
                    \(template)
                    \(1.tab)var stubbed\(name.capitalizeFirstLetter)\(paramsInputs)Result: \(returnTypeName)!
                    \(1.tab)\n
                    """
                }
            }
            var stubbedCompletionResult = ""

            if !params.isEmpty {
                params.forEach { param in
                    if param.type.typeName.contains("->") || param.type.typeName.contains("escaping") {
                        var stubbedType = param.type.typeName.replacingOccurrences(of: "@escaping", with: "")
                        stubbedType = stubbedType.trimmingCharacters(in: .whitespaces)
                        let stubbedTupleItems = stubbedType.components(separatedBy: "->")
                        var firstItem = stubbedTupleItems.first?.trimmingCharacters(in: .whitespaces) ?? "Void"
                        var tempFirstItem = firstItem
                        tempFirstItem.removeAll(where: { $0 == "(" || $0 == ")" })

                        // if is not a tuple
                        if !tempFirstItem.contains(",") {
                            firstItem = tempFirstItem
                        }
                        let optionalIfNeeded = stubbedType.last == "?" ? "?" : ""
                        var stubbedName = firstItem.isEmpty ? "shouldInvoke\(identifier.capitalizeFirstLetter)\(param.name.capitalizeFirstLetter)" : "stubbed\(identifier.capitalizeFirstLetter)\(param.name.capitalizeFirstLetter)"
                        stubbedName += stubbedName.contains("Result") ? "" : "Result"
                        let stubbedIfCodes = firstItem.isEmpty
                        ? "if \(stubbedName) {\n\t\t\t\(param.name)\(optionalIfNeeded)()\n\t\t}"
                        : "if let \(stubbedName) = \(stubbedName) {\n\t\t\t\(param.name)\(optionalIfNeeded)(\(stubbedName).0)\n\t\t}"
                        
                        stubbedCompletionResult = "\(stubbedCompletionResult)\(2.tab)\(stubbedIfCodes)"
                        var invokedCompletionVariable = ""
                        if stubbedTupleItems.count == 1 {
                            invokedCompletionVariable = "\(acl)var \(stubbedName)\(firstItem.isEmpty ?  " = false" : ": (\(firstItem)")"
                        } else {
                            let lastItem = stubbedTupleItems.last?.trimmingCharacters(in: .whitespaces) ?? "(unknown)"
                            invokedCompletionVariable = "\(acl)var \(stubbedName)\(firstItem.isEmpty ?  " = false" : ": (\(firstItem),\(lastItem)") "
                        }

                        if !firstItem.isEmpty {
                            invokedCompletionVariable += stubbedType.last == "?" ? "" : ")?"
                        }
                        template = """
                        \(template)
                        \(1.tab)\(invokedCompletionVariable)
                        """

                    }
                }
            }

            template = """
            \(template)
            \(1.tab)\(acl)\(staticStr)\(overrideStr)\(modifierTypeStr)\(keyword)\(name)\(genericTypesStr)(\(paramDeclsStr)) \(suffixStr)\(returnStr)\(genericWhereStr){\(wrapped)
            """

            if params.isEmpty {
                template = """
                \(template)
                \(2.tab)invokedList.append(.\(identifier))
                """
            } else {
                let paramsInputs = params.map{$0.name + ": " + $0.name}.joined(separator: ", ")
                template = """
                \(template)
                \(2.tab)invokedList.append(.\(identifier)(\(paramsInputs)))
                """
            }

            if stubbedCompletionResult.count > 0 {
                template = """
                \(template)
                \(stubbedCompletionResult)
                """
            }

            if !returnType.isUnknown {
                if params.isEmpty {
                    template = """
                    \(template)
                    \(2.tab)return stubbed\(name.capitalizeFirstLetter)Result
                    \(1.tab)}
                    """
                } else {
                    let paramsInputs = params.map{$0.name.capitalizeFirstLetter}.joined(separator: "")
                    template = """
                    \(template)
                    \(2.tab)return stubbed\(name.capitalizeFirstLetter)\(paramsInputs.capitalizeFirstLetter)Result
                    \(1.tab)}
                    """
                }
            } else {
                template = """
                \(template)
                \t}
                """
            }
        }

        return template
    }
}

