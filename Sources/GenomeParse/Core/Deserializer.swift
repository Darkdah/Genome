//
//  Deserializer.swift
//  Genome
//
//  Created by McQuilkin, Brandon on 5/9/16.
//
//

//---------------------------------
// MARK: Deserialization Errors
//---------------------------------

/// Errors that can be thrown by deserializers.
public enum DeserializationError: ErrorProtocol {
    /// Some unknown error, usually indicates something not yet implemented.
    case Unknown
    /// Input data was either empty or contained only whitespace.
    case EmptyInput
    /// Some character that does not follow file specifications was found.
    case UnexpectedCharacter(lineNumber: UInt, characterNumber: UInt)
    /// A string was opened but never closed.
    case UnterminatedString
    /// Any unicode parsing errors will result in this error.
    case InvalidUnicode
    /// A keyword, like `null`, `true`, or `false` was expected but something else was in the input.
    case UnexpectedKeyword(lineNumber: UInt, characterNumber: UInt)
    /// Encountered a number that couldn't be stored, or is invalid.
    case InvalidNumber(lineNumber: UInt, characterNumber: UInt)
    /// End of file reached, not always an actual error.
    case EndOfFile
}

//---------------------------------
// MARK: Deserialzation Progress
//---------------------------------

/// The protocol that informs the delegate how much data has been processed.
public protocol DeserializationProgressDelegate {
    /**
     Notifies the delegate that the deserializer has processed data.
     - parameter totalBytesProcessed: The total number of bytes that has been processed.
     - parameter totalBytesExpectedToRead: The total number of bytes that are expected to be read.
     */
    func deserializerDidProcessData(totalBytesProcessed: Int64, totalBytesExpectedToRead: Int64)
}

//---------------------------------
// MARK: Deserialization Delegate
//---------------------------------

/// The r=protocol that allows a delegate to process the output data stream.
internal protocol DeserializerDeserializationDelegate {
    /**
     Notifies the delegate that the deserializer will be deserializing a node of the given type.
     - parameter node: An empty node representing the type of root node that will be processed.
     */
    func deserializerStartingRootNodeOfType(node: Node)
    
    /**
     Notifies the delegate that the deserializer has deserialized a direct child of the root node from the given data.
     - parameter node: The node that was deserialized.
     - parameter key: The key of the node if the root node is of object type.
     */
    func deserializerDeserializedNode(node: Node, key: String?)
    
    /**
     Notifies the delegate that the deserializer has finished deserializing the current root node.
     */
    func deserializerCompletedRootNode()
}

/// An internal class to collect the data stream into a string.
internal class DeserializerConcatenate: DeserializerDeserializationDelegate {
    var output: Node?
    
    func deserializerStartingRootNodeOfType(node: Node) {
        output = node
    }
    
    func deserializerDeserializedNode(node: Node, key: String?) {
        if let output = output {
            if let key = key {
                guard case var .object(object) = output else {
                    return
                }
                object[key] = node
                self.output = .object(object)
            } else {
                guard case var .array(array) = output else {
                    return
                }
                array.append(node)
                self.output = .array(array)
            }
        }
    }
    
    func deserializerCompletedRootNode() {
        // Do nothing.
    }
}

//---------------------------------
// MARK: Deserializer
//---------------------------------

/**
 Deserializes file data into a structure of `Node` objects.
 */
public class Deserializer {
    
    //---------------------------------
    // MARK: Properties
    //---------------------------------
    
    /// The delegate that will get notified of the progress that the deserialzer is making.
    public var progressDelegate: DeserializationProgressDelegate?
    
    /// The data being processed.
    internal var data: String.UnicodeScalarView
    
    /// A generator that iterates of the data to be deserialized.
    internal var generator: String.UnicodeScalarView.Generator
    
    // The current scalar.
    internal private(set) var scalar: UnicodeScalar!
    
    /// The current index the generator is on.
    private var index: Int = -1
    
    /// The current line number.
    internal var lineNumber: UInt = 0
    
    /// The current character number.
    internal var characterNumber: UInt = 0
    
    /// The deserialization delegate.
    internal var deserializationDelegate: DeserializerDeserializationDelegate = DeserializerConcatenate()
    
    //---------------------------------
    // MARK: Initalization
    //---------------------------------
    
    /**
     Initalizes a deserializer with the given data.
     - parameter data: The data to parse into a node.
     - returns: A new deserializer object that will parse the given data.
     */
    public convenience init(data: String) {
        self.init(data: data.unicodeScalars)
    }
    
    /**
     Initalizes a deserializer with the given data.
     - parameter data: The data to parse into a node.
     - returns: A new deserializer object that will parse the given data.
     */
    public required init(data: String.UnicodeScalarView) {
        self.data = data
        self.generator = data.makeIterator()
    }
    
    //---------------------------------
    // MARK: Parsing
    //---------------------------------
    
    /**
     Deserializes the data given into a data node if possible.
     - returns: A node representing the data the deserializer was initialized with.
     - throws: Throws a `DeserializationError` if the data is unable to be deserialized.
     */
    public func parse() throws -> Node {
        try parse(data: data)
        return try finish()
    }
    
    /**
     Deserializes the data given into a data node if possible. This will continue to accept data to append to the node until `finish()` is called.
     - note: This is used by the stream deserializers.
     - throws: Throws a `DeserializationError` if the data is unable to be deserialized.
     */
    internal func parse(data: String.UnicodeScalarView) throws {
        // Trim the current data.
        if index > 0 {
            self.data = self.data.dropFirst(index)
        }
        // Append the new data
        self.data.append(contentsOf: data)
        // Reset the generator
        generator = self.data.makeIterator()
        try nextScalar()
    }
    
    /**
     Moves the parser's "index" to the next character in the sequence.
     - throws: `DeserializationError.EndOfFile`. Usually not a fatal error.
     */
    internal final func nextScalar() throws {
        // If there is a next character
        if let sc = generator.next() {
            // Set the current scalar to the next one.
            scalar = sc
            // Increment the index
            index += 1
            // Increment which character we are on.
            characterNumber += 1
            // Increment the line number if necessary.
            if scalar == FileConstants.carriageReturn || scalar == FileConstants.formFeed {
                characterNumber = 0
                lineNumber += 1
            }
        } else {
            // We reached the end of the file.
            throw DeserializationError.EndOfFile
        }
    }
    
    /**
     Finish deserializing the data. This method signals the deserializer that no more data will be appended. If more data is expected, an error will be thrown.
     - throws: Throws a `DeserializationError` if the deserializer is expecting more data.
     - returns: A node representing the deserialized data.
     */
    internal func finish() throws -> Node {
        fatalError("This method must be overriden by subclasses.")
    }
    
}

