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
import SourceKittenFramework


/// TODO: remove this file once SwiftScanner is added as a dependency and the following ACLs become public.

private let unknown = "Unknown"

extension Structure {
    
    /// The substructures of this structure.
    var substructures: [Structure] {
        let substructures = (dictionary["key.substructure"] as? [SourceKitRepresentable]) ?? []
        
        let result = substructures.compactMap { (substructure: SourceKitRepresentable) -> Structure? in
            if let structure = substructure as? [String: SourceKitRepresentable] {
                return Structure(sourceKitResponse: structure)
            } else {
                return nil
            }
        }
        return result
    }
    
    var name: String {
        // A type must have a name.
        return dictionary["key.name"] as? String ?? unknown
    }
    
    var kind: String {
        return dictionary["key.kind"] as? String ?? unknown
    }
    var typeName: String {
        return dictionary["key.typename"] as? String ?? unknown
    }

    var hasAvailableAttribute: Bool {
        return kind == SwiftDeclarationAttributeKind.available.rawValue
    }
    
    var attributes: [String]? {
        if let subs = dictionary["key.attributes"] as? [SourceKitRepresentable] {
            let result = subs.compactMap { (sub: SourceKitRepresentable) -> String? in
                if let child = sub as? [String: SourceKitRepresentable], let val = child["key.attribute"] as? String, let leaf = val.components(separatedBy: ".").last {
                    return leaf
                }
                return nil
            }
            return result
        }
        return nil
    }
    
    var accessControlLevel: String {
        if let access = dictionary["key.accessibility"] as? String, let acl = access.components(separatedBy: ".").last {
            return acl
        }
        return unknown
    }
    
    var isInstanceVariable: Bool {
        return kind == SwiftDeclarationKind.varInstance.rawValue
    }
    
    var isStaticVariable: Bool {
        return kind == SwiftDeclarationKind.varStatic.rawValue
    }
    
    var isStaticMethod: Bool {
        return kind == SwiftDeclarationKind.functionMethodStatic.rawValue
    }
    
    var isProtocol: Bool {
        return kind == SwiftDeclarationKind.protocol.rawValue
    }
    
    var isClass: Bool {
        return kind == SwiftDeclarationKind.class.rawValue
    }
    
    var isInstanceMethod: Bool {
        return kind == SwiftDeclarationKind.functionMethodInstance.rawValue
    }
    
    var isParameter: Bool {
        return kind == "source.lang.swift.decl.var.parameter"
    }
    
    var inheritedTypes: [String] {
        let types = dictionary["key.inheritedtypes"] as? [SourceKitRepresentable] ?? []
        return types.compactMap { (item: SourceKitRepresentable) -> String? in
            (item as? [String: String])?["key.name"]
        }
    }
    
    func extractPart(_ file: String) -> String {
        let start = dictionary["key.bodyoffset"] as? Int64 ?? -1
        let len = dictionary["key.bodylength"] as? Int64 ?? 0
        if start >= 0 && len > 0 {
            if start - 1 + len > file.count {
                print("No content found", start, len, start - 1 + len, file.count)
                return ""
            }
            let begin = file.index(file.startIndex, offsetBy: start - 1)
            let end = file.index(file.startIndex, offsetBy: start - 1 + len)
            let body = file[begin ..< end]
            return String(body)
        } else {
            return ""
        }
    }
}

func scanDirectory(_ path: String, with callBack: (String) -> Void) {
    let errorHandler = { (url: URL, error: Error) -> Bool in
        fatalError("Failed to traverse \(url) with error \(error).")
    }
    if let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles], errorHandler: errorHandler) {
        while let nextObjc = enumerator.nextObject() {
            if let fileUrl = nextObjc as? URL {
                callBack(fileUrl.path)
            }
        }
    }
}

func scanPaths(_ paths: [String], with callBack: (String) -> Void) {
    for path in paths {
        scanDirectory(path, with: callBack)
    }
}

func fileParse(_ path: String,
               lock: NSLock? = nil,
               exclusionList: [String]? = nil,
               process: (Structure, File) -> ()) -> Bool {
    let fileName = URL(fileURLWithPath: path).lastPathComponent
    guard fileName.shouldParse(with: exclusionList) else { return false }
    
    guard let file = File(path: path) else { return false }
    
    if let result = try? Structure(file: file) {
        for substructure in result.substructures {
            lock?.lock()
            process(substructure, file)
            lock?.unlock()
        }
    }
    
    return true
}

