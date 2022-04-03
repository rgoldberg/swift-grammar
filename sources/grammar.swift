@frozen public 
struct ParsingError<Index>:TraceableError, CustomStringConvertible 
{
    @frozen public 
    struct Frame 
    {
        public 
        let index:Index 
        public 
        let rule:Any.Type 
        public 
        let construction:Any.Type 
        @inlinable public 
        init(index:Index, rule:Any.Type, construction:Any.Type)
        {
            self.index          = index 
            self.rule           = rule 
            self.construction   = construction
        }
    }
    public static 
    var namespace:String 
    {
        "parsing error"
    }
    public 
    let problem:Error, 
        index:Index,
        trace:[Frame]
    @inlinable public 
    init(at index:Index, because problem:Error, trace:[Frame])
    {
        self.problem    = problem
        self.index      = index 
        self.trace      = trace
    }
    public 
    var context:[String] 
    {
        trace.map 
        {
            if $0.construction is Void.Type
            {
                return "while validating pattern '\($0.rule)'"
            }
            else 
            {
                return "while parsing value of type '\($0.construction)' by rule '\($0.rule)'"
            }
        }
    } 
    public 
    var next:Error? 
    {
        self.problem 
    }
    
    static 
    func annotate<Background>(_ range:Range<Index>, on background:Background, 
        line render:(Background.SubSequence) -> String, 
        newline predicate:(Background.Element) -> Bool) 
        -> String 
        where Background:BidirectionalCollection, Background.Index == Index
    {
        // `..<` means this will print the previous line if the problematic 
        // index references the newline itself
        let beginning:String, 
            middle:String
        if let start:Index  = background[..<range.lowerBound].lastIndex (where: predicate)
        {
            // can only remove newline if there is actually a preceeding newline 
            beginning = render(background[start..<range.lowerBound].dropFirst())
        }
        else 
        {
            beginning = render(background[..<range.lowerBound])
        } 
        let line:String
        let   end:Index     = background[range.lowerBound...].firstIndex(where: predicate) ?? 
            background.endIndex
        if range.upperBound < end 
        {
            middle  = render(background[range])
            line    = beginning + middle + render(background[range.upperBound..<end])
        }
        else 
        {
            middle  = render(background[range.lowerBound..<end])
            line    = beginning + middle 
        }
        return 
            """
            \(line)
            \(String.init(repeating: " ", count: beginning.count))^\(String.init(repeating: "~", count: middle.count).dropLast())
            """
    }
    public 
    func annotate<Background>(source background:Background, 
        line:(Background.SubSequence) -> String, newline:(Background.Element) -> Bool) 
        -> String 
        where Background:BidirectionalCollection, Background.Index == Index
    {
        """
        \(String.init(reflecting: type(of: self.problem))): \(self.problem)
        \(Self.annotate(background.index(before: self.index) ..< self.index, on: background, line: line, newline: newline))
        \(self.trace.map
        {
            (frame:Frame) in
            
            let heading:String 
            if frame.construction is Void.Type
            {
                heading = "note: expected pattern '\(String.init(reflecting: frame.rule))'"
            }
            else 
            {
                heading = "note: while parsing value of type '\(String.init(reflecting: frame.construction))' by rule '\(String.init(reflecting: frame.rule))'"
            }
            return "\(heading)\n\(Self.annotate(frame.index ..< self.index, on: background, line: line, newline: newline))"
        }.reversed().joined(separator: "\n"))
        """
    }
}
public 
protocol ParsingRule 
{
    associatedtype Location
    associatedtype Terminal 
    associatedtype Construction
    
    static 
    func parse<Diagnostics>(_ input:inout ParsingInput<Diagnostics>) 
        throws -> Construction
        where   Diagnostics:ParsingDiagnostics, 
                Diagnostics.Source.Index == Location, 
                Diagnostics.Source.Element == Terminal
}
public
protocol ParsingDiagnostics 
{
    associatedtype Source where Source:Collection 
    associatedtype Breadcrumb 
    
    init()
    
    mutating 
    func push<Rule, Construction>(index:Source.Index, for _:Construction.Type, by _:Rule.Type) 
        -> Breadcrumb
    mutating 
    func pop()
    mutating 
    func reset(index:inout Source.Index, to:Breadcrumb, because:inout Error) 
}
public 
enum Grammar 
{
    @frozen public 
    struct NoDiagnostics<Source>:ParsingDiagnostics where Source:Collection
    {
        @inlinable public 
        init() 
        {
        }
        // force inlining because these functions ignore most of their inputs, and 
        // don’t contain many instructions (if any)
        @inline(__always)
        @inlinable public 
        func push<Rule, Construction>(index:Source.Index, for _:Construction.Type, by _:Rule.Type) 
            -> Source.Index
        {
            index
        }
        @inline(__always)
        @inlinable public 
        func pop()
        {
        }
        @inline(__always)
        @inlinable public 
        func reset(index:inout Source.Index, to breadcrumb:Source.Index, because _:inout Error) 
        {
            index = breadcrumb 
        }
    }
    @frozen public 
    struct DefaultDiagnostics<Source>:ParsingDiagnostics where Source:Collection
    {
        public 
        var stack:[ParsingError<Source.Index>.Frame], 
            frontier:ParsingError<Source.Index>?
        @inlinable public 
        init() 
        {
            self.stack      = []
            self.frontier   = nil 
        }
        @inlinable public mutating 
        func push<Rule, Construction>(index:Source.Index, for _:Construction.Type, by _:Rule.Type)
        {
            self.stack.append(.init(index: index, rule: Rule.self, construction: Construction.self))
        }
        @inlinable public mutating 
        func pop()
        {
            self.stack.removeLast()
        }
        @inlinable public mutating 
        func reset(index:inout Source.Index, to _:Void, because error:inout Error)
        {
            defer 
            {
                index = self.stack.removeLast().index 
            }
            if  error is ParsingError<Source.Index> 
            {
                return 
            }
            if let diagnostic:ParsingError<Source.Index> = self.frontier, index < diagnostic.index
            {
                // we did not make it as far as the previous most-successful parse 
                error           = diagnostic 
            }
            else 
            {
                let diagnostic:ParsingError<Source.Index> = .init(at: index, 
                    because: error, trace: self.stack) 
                self.frontier   = diagnostic 
                error           = diagnostic
            }
        }
    }
}
@frozen
public 
struct ParsingInput<Diagnostics> where Diagnostics:ParsingDiagnostics
{
    public  
    let source:Diagnostics.Source
    public 
    var index:Diagnostics.Source.Index 
    public 
    var diagnostics:Diagnostics
    @inlinable public 
    init(_ source:Diagnostics.Source)
    {
        self.source         = source 
        self.index          = source.startIndex 
        self.diagnostics    = .init()
    }
    @inlinable public 
    subscript(_ index:Diagnostics.Source.Index) -> Diagnostics.Source.Element 
    {
        self.source[index]
    }
    @inlinable public 
    subscript<Indices>(_ range:Indices) -> Diagnostics.Source.SubSequence 
        where Indices:RangeExpression, Indices.Bound == Diagnostics.Source.Index 
    {
        self.source[range.relative(to: self.source)]
    }
    
    @inlinable public mutating 
    func next() -> Diagnostics.Source.Element?
    {
        guard self.index != self.source.endIndex
        else 
        {
            return nil 
        }
        defer 
        {
            self.index = self.source.index(after: self.index)
        }
        return self.source[self.index]
    }
    @inlinable public mutating 
    func group<Rule, Construction>(_:Rule.Type, _ body:(inout Self) throws -> Construction) 
        throws -> Construction
    {
        let breadcrumb:Diagnostics.Breadcrumb = 
            self.diagnostics.push(index: self.index, for: Construction.self, by: Rule.self)
        do 
        {
            let construction:Construction = try body(&self)
            self.diagnostics.pop()
            return construction 
        }
        catch var error 
        {
            self.diagnostics.reset(index: &self.index, to: breadcrumb, because: &error)
            throw error
        }
    }
    
    @inlinable public mutating 
    func parse<Rule>(as _:Rule.Type) throws -> Rule.Construction 
        where   Rule:ParsingRule, Rule.Location == Diagnostics.Source.Index, Rule.Terminal == Diagnostics.Source.Element
    {
        try self.group(Rule.self){ try Rule.parse(&$0) }
    }
    
    @discardableResult 
    @inlinable public mutating 
    func parse<T0, T1>(as _:(T0, T1).Type) throws 
        -> (T0.Construction, T1.Construction) 
        where   T0:ParsingRule, T0.Location == Diagnostics.Source.Index, T0.Terminal == Diagnostics.Source.Element, 
                T1:ParsingRule, T1.Location == Diagnostics.Source.Index, T1.Terminal == Diagnostics.Source.Element 
    {
        try self.group((T0, T1).self)
        {
            let list:(T0.Construction, T1.Construction) 
            list.0 = try T0.parse(&$0)
            list.1 = try T1.parse(&$0)
            return list
        }
    }
    @discardableResult 
    @inlinable public mutating 
    func parse<T0, T1, T2>(as _:(T0, T1, T2).Type) throws 
        -> (T0.Construction, T1.Construction, T2.Construction) 
        where   T0:ParsingRule, T0.Location == Diagnostics.Source.Index, T0.Terminal == Diagnostics.Source.Element, 
                T1:ParsingRule, T1.Location == Diagnostics.Source.Index, T1.Terminal == Diagnostics.Source.Element,
                T2:ParsingRule, T2.Location == Diagnostics.Source.Index, T2.Terminal == Diagnostics.Source.Element 
    {
        try self.group((T0, T1, T2).self)
        {
            let list:(T0.Construction, T1.Construction, T2.Construction) 
            list.0 = try T0.parse(&$0)
            list.1 = try T1.parse(&$0)
            list.2 = try T2.parse(&$0)
            return list
        }
    }
    @discardableResult 
    @inlinable public mutating 
    func parse<T0, T1, T2, T3>(as _:(T0, T1, T2, T3).Type) throws 
        -> (T0.Construction, T1.Construction, T2.Construction, T3.Construction) 
        where   T0:ParsingRule, T0.Location == Diagnostics.Source.Index, T0.Terminal == Diagnostics.Source.Element, 
                T1:ParsingRule, T1.Location == Diagnostics.Source.Index, T1.Terminal == Diagnostics.Source.Element,
                T2:ParsingRule, T2.Location == Diagnostics.Source.Index, T2.Terminal == Diagnostics.Source.Element,
                T3:ParsingRule, T3.Location == Diagnostics.Source.Index, T3.Terminal == Diagnostics.Source.Element 
    {
        try self.group((T0, T1, T2, T3).self)
        {
            let list:(T0.Construction, T1.Construction, T2.Construction, T3.Construction) 
            list.0 = try T0.parse(&$0)
            list.1 = try T1.parse(&$0)
            list.2 = try T2.parse(&$0)
            list.3 = try T3.parse(&$0)
            return list
        }
    }
    @discardableResult 
    @inlinable public mutating 
    func parse<T0, T1, T2, T3, T4>(as _:(T0, T1, T2, T3, T4).Type) throws 
        -> (T0.Construction, T1.Construction, T2.Construction, T3.Construction, T4.Construction) 
        where   T0:ParsingRule, T0.Location == Diagnostics.Source.Index, T0.Terminal == Diagnostics.Source.Element, 
                T1:ParsingRule, T1.Location == Diagnostics.Source.Index, T1.Terminal == Diagnostics.Source.Element,
                T2:ParsingRule, T2.Location == Diagnostics.Source.Index, T2.Terminal == Diagnostics.Source.Element,
                T3:ParsingRule, T3.Location == Diagnostics.Source.Index, T3.Terminal == Diagnostics.Source.Element,
                T4:ParsingRule, T4.Location == Diagnostics.Source.Index, T4.Terminal == Diagnostics.Source.Element 
    {
        try self.group((T0, T1, T2, T3, T4).self)
        {
            let list:(T0.Construction, T1.Construction, T2.Construction, T3.Construction, T4.Construction) 
            list.0 = try T0.parse(&$0)
            list.1 = try T1.parse(&$0)
            list.2 = try T2.parse(&$0)
            list.3 = try T3.parse(&$0)
            list.4 = try T4.parse(&$0)
            return list
        }
    }
    @discardableResult 
    @inlinable public mutating 
    func parse<T0, T1, T2, T3, T4, T5>(as _:(T0, T1, T2, T3, T4, T5).Type) throws 
        -> (T0.Construction, T1.Construction, T2.Construction, T3.Construction, T4.Construction, T5.Construction) 
        where   T0:ParsingRule, T0.Location == Diagnostics.Source.Index, T0.Terminal == Diagnostics.Source.Element, 
                T1:ParsingRule, T1.Location == Diagnostics.Source.Index, T1.Terminal == Diagnostics.Source.Element,
                T2:ParsingRule, T2.Location == Diagnostics.Source.Index, T2.Terminal == Diagnostics.Source.Element,
                T3:ParsingRule, T3.Location == Diagnostics.Source.Index, T3.Terminal == Diagnostics.Source.Element,
                T4:ParsingRule, T4.Location == Diagnostics.Source.Index, T4.Terminal == Diagnostics.Source.Element,
                T5:ParsingRule, T5.Location == Diagnostics.Source.Index, T5.Terminal == Diagnostics.Source.Element 
    {
        try self.group((T0, T1, T2, T3, T4, T5).self)
        {
            let list:(T0.Construction, T1.Construction, T2.Construction, T3.Construction, T4.Construction, T5.Construction) 
            list.0 = try T0.parse(&$0)
            list.1 = try T1.parse(&$0)
            list.2 = try T2.parse(&$0)
            list.3 = try T3.parse(&$0)
            list.4 = try T4.parse(&$0)
            list.5 = try T5.parse(&$0)
            return list
        }
    }
    @discardableResult 
    @inlinable public mutating 
    func parse<T0, T1, T2, T3, T4, T5, T6>(as _:(T0, T1, T2, T3, T4, T5, T6).Type) throws 
        -> (T0.Construction, T1.Construction, T2.Construction, T3.Construction, T4.Construction, T5.Construction, T6.Construction) 
        where   T0:ParsingRule, T0.Location == Diagnostics.Source.Index, T0.Terminal == Diagnostics.Source.Element, 
                T1:ParsingRule, T1.Location == Diagnostics.Source.Index, T1.Terminal == Diagnostics.Source.Element,
                T2:ParsingRule, T2.Location == Diagnostics.Source.Index, T2.Terminal == Diagnostics.Source.Element,
                T3:ParsingRule, T3.Location == Diagnostics.Source.Index, T3.Terminal == Diagnostics.Source.Element,
                T4:ParsingRule, T4.Location == Diagnostics.Source.Index, T4.Terminal == Diagnostics.Source.Element,
                T5:ParsingRule, T5.Location == Diagnostics.Source.Index, T5.Terminal == Diagnostics.Source.Element,
                T6:ParsingRule, T6.Location == Diagnostics.Source.Index, T6.Terminal == Diagnostics.Source.Element 
    {
        try self.group((T0, T1, T2, T3, T4, T5, T6).self)
        {
            let list:(T0.Construction, T1.Construction, T2.Construction, T3.Construction, T4.Construction, T5.Construction, T6.Construction) 
            list.0 = try T0.parse(&$0)
            list.1 = try T1.parse(&$0)
            list.2 = try T2.parse(&$0)
            list.3 = try T3.parse(&$0)
            list.4 = try T4.parse(&$0)
            list.5 = try T5.parse(&$0)
            list.6 = try T6.parse(&$0)
            return list
        }
    }
}
extension ParsingInput
{
    // this overload will be preferred over the `throws` overload
    @inlinable public mutating 
    func parse<Rule>(as _:Rule?.Type) -> Rule.Construction? 
        where   Rule:ParsingRule, Rule.Location == Diagnostics.Source.Index, Rule.Terminal == Diagnostics.Source.Element
    {
        try? self.parse(as: Rule.self)
    }
    @inlinable public mutating 
    func parse<Rule>(as _:Rule.Type, in _:Void.Type) 
        where   Rule:ParsingRule, Rule.Location == Diagnostics.Source.Index, Rule.Terminal == Diagnostics.Source.Element, 
                Rule.Construction == Void 
    {
        while let _:Void = self.parse(as: Rule?.self)
        {
        }
    }
    @inlinable public mutating 
    func parse<Rule, Vector>(as _:Rule.Type, in _:Vector.Type) -> Vector
        where   Rule:ParsingRule, Rule.Location == Diagnostics.Source.Index, Rule.Terminal == Diagnostics.Source.Element, 
                Rule.Construction == Vector.Element, 
                Vector:RangeReplaceableCollection
    {
        var vector:Vector = .init()
        while let element:Rule.Construction = self.parse(as: Rule?.self)
        {
            vector.append(element)
        }
        return vector
    }
    @inlinable public mutating 
    func parse(prefix count:Int) throws -> Diagnostics.Source.SubSequence
    {
        guard let index:Diagnostics.Source.Index = 
            self.source.index(self.index, offsetBy: count, limitedBy: self.source.endIndex)
        else 
        {
            throw Grammar.Expected<Any>.init()
        }
        
        let prefix:Diagnostics.Source.SubSequence = self.source[self.index ..< index]
        self.index = index 
        return prefix
    }
}
// these extensions are mainly useful when defined as part of a tuple rule.
// otherwise, the overloads in the previous section of code should be preferred
extension Optional:ParsingRule where Wrapped:ParsingRule 
{
    public 
    typealias Location  = Wrapped.Location
    public 
    typealias Terminal  = Wrapped.Terminal 
    
    @inlinable public static 
    func parse<Diagnostics>(_ input:inout ParsingInput<Diagnostics>) -> Wrapped.Construction?
        where   Diagnostics:ParsingDiagnostics,
                Diagnostics.Source.Index == Location,
                Diagnostics.Source.Element == Terminal
    {
        // will choose non-throwing overload, so no infinite recursion will occur
        input.parse(as: Wrapped?.self)
    }
} 
extension Array:ParsingRule where Element:ParsingRule
{
    public
    typealias Location = Element.Location
    public
    typealias Terminal = Element.Terminal 
    
    @inlinable public static 
    func parse<Diagnostics>(_ input:inout ParsingInput<Diagnostics>) -> [Element.Construction]
        where   Diagnostics:ParsingDiagnostics,
                Diagnostics.Source.Index == Location,
                Diagnostics.Source.Element == Terminal
    {
        input.parse(as: Element.self, in: [Element.Construction].self)
    }
}

extension Grammar 
{
    public 
    enum Encoding<Location, Terminal> 
    {
    }
}
extension Grammar 
{
    @frozen public
    struct Expected<T>:Error, CustomStringConvertible 
    {
        @inlinable public
        init()
        {
        }
        public
        var description:String 
        {
            "expected construction by rule '\(T.self)'"
        }
    }
    @frozen public
    struct ExpectedRegion<Base, Exclusion>:Error, CustomStringConvertible 
    {
        @inlinable public
        init()
        {
        }
        public
        var description:String 
        {
            "value of type '\(Base.self)' would also be a valid value of '\(Exclusion.self)'"
        }
    }
    public
    enum End<Location, Terminal>:ParsingRule 
    {
        @inlinable public static 
        func parse<Diagnostics>(_ input:inout ParsingInput<Diagnostics>) throws 
            where   Diagnostics:ParsingDiagnostics, 
                    Diagnostics.Source.Index == Location, 
                    Diagnostics.Source.Element == Terminal
        {
            if let _:Terminal = input.next() 
            {
                throw Expected<Never>.init()
            }
        }
    }
    @inlinable public static 
    func parse<Source, Root>(diagnosing source:Source, as _:Root.Type) throws -> Root.Construction
        where   Source:Collection, Root:ParsingRule, 
                Root.Location == Source.Index, Root.Terminal == Source.Element
    {
        var input:ParsingInput<DefaultDiagnostics<Source>> = .init(source)
        let construction:Root.Construction = try input.parse(as: Root.self)
        try input.parse(as: End<Root.Location, Root.Terminal>.self)
        return construction
    }
    @inlinable public static 
    func parse<Source, Root>(_ source:Source, as _:Root.Type) throws -> Root.Construction
        where   Source:Collection, Root:ParsingRule, 
                Root.Location == Source.Index, Root.Terminal == Source.Element
    {
        var input:ParsingInput<NoDiagnostics<Source>> = .init(source)
        let construction:Root.Construction = try input.parse(as: Root.self)
        try input.parse(as: End<Root.Location, Root.Terminal>.self)
        return construction
    }
    @inlinable public static 
    func parse<Source, Rule, Vector>(_ source:Source, as _:Rule.Type, in _:Vector.Type) throws -> Vector
        where   Source:Collection, Rule:ParsingRule, 
                Rule.Location == Source.Index, Rule.Terminal == Source.Element, 
                Vector:RangeReplaceableCollection, Vector.Element == Rule.Construction
    {
        var input:ParsingInput<NoDiagnostics<Source>> = .init(source)
        let construction:Vector = input.parse(as: Rule.self, in: Vector.self)
        try input.parse(as: End<Rule.Location, Rule.Terminal>.self)
        return construction
    }
}
extension Grammar 
{
    @available(*, deprecated, renamed: "LiteralRule")
    public 
    typealias TerminalSequence  = LiteralRule
    
    @available(*, deprecated, renamed: "TerminalRule")
    public 
    typealias TerminalClass     = TerminalRule
}


extension Grammar 
{
    public 
    enum Discard<Rule>:ParsingRule 
        where   Rule:ParsingRule, Rule.Construction == Void
    {
        public 
        typealias Location = Rule.Location
        public 
        typealias Terminal = Rule.Terminal 
        @inlinable public static 
        func parse<Diagnostics>(_ input:inout ParsingInput<Diagnostics>) 
            where   Diagnostics:ParsingDiagnostics,
                    Diagnostics.Source.Index == Location,
                    Diagnostics.Source.Element == Terminal
        {
            input.parse(as: Rule.self, in: Void.self)
        }
    }
    public 
    enum Collect<Rule, Construction>:ParsingRule 
        where   Rule:ParsingRule, Rule.Construction == Construction.Element,
                Construction:RangeReplaceableCollection
    {
        public 
        typealias Location = Rule.Location
        public 
        typealias Terminal = Rule.Terminal 
        @inlinable public static 
        func parse<Diagnostics>(_ input:inout ParsingInput<Diagnostics>) -> Construction
            where   Diagnostics:ParsingDiagnostics,
                    Diagnostics.Source.Index == Location,
                    Diagnostics.Source.Element == Terminal
        {
            input.parse(as: Rule.self, in: Construction.self)
        }
    }
    public 
    enum Reduce<Rule, Construction>:ParsingRule 
        where   Rule:ParsingRule, Rule.Construction == Construction.Element,
                Construction:RangeReplaceableCollection
    {
        public 
        typealias Location = Rule.Location
        public 
        typealias Terminal = Rule.Terminal 
        @inlinable public static 
        func parse<Diagnostics>(_ input:inout ParsingInput<Diagnostics>) throws -> Construction
            where   Diagnostics:ParsingDiagnostics,
                    Diagnostics.Source.Index == Location,
                    Diagnostics.Source.Element == Terminal
        {
            var vector:Construction = .init()
                vector.append(try input.parse(as: Rule.self))
            while let next:Rule.Construction = input.parse(as: Rule?.self)
            {
                vector.append(next)
            }
            return vector
        }
    }
    public 
    enum Join<Rule, Separator, Construction>:ParsingRule
        where   Rule:ParsingRule, Separator:ParsingRule,
                Rule.Location == Separator.Location, 
                Rule.Terminal == Separator.Terminal, 
                Separator.Construction == Void, 
                Rule.Construction == Construction.Element, 
                Construction:RangeReplaceableCollection
    {
        public 
        typealias Terminal = Rule.Terminal
        public 
        typealias Location = Rule.Location
        @inlinable public static 
        func parse<Diagnostics>(_ input:inout ParsingInput<Diagnostics>) throws -> Construction
            where   Diagnostics:ParsingDiagnostics,
                    Diagnostics.Source.Index == Location,
                    Diagnostics.Source.Element == Terminal
        {
            var vector:Construction = .init()
                vector.append(try input.parse(as: Rule.self))
            while let (_, next):(Void, Rule.Construction)  = try? input.parse(as: (Separator, Rule).self)
            {
                vector.append(next)
            }
            return vector
        }
    }
}
extension Grammar 
{
    public 
    enum Pad<Rule, Padding>:ParsingRule
        where   Rule:ParsingRule, Padding:ParsingRule, 
                Rule.Location == Padding.Location,
                Rule.Terminal == Padding.Terminal, 
                Padding.Construction == Void
    {
        public 
        typealias Terminal = Rule.Terminal
        public 
        typealias Location = Rule.Location
        @inlinable public static 
        func parse<Diagnostics>(_ input:inout ParsingInput<Diagnostics>) throws -> Rule.Construction
            where   Diagnostics:ParsingDiagnostics,
                    Diagnostics.Source.Index == Location,
                    Diagnostics.Source.Element == Terminal
        {
            input.parse(as: Padding.self, in: Void.self)
            let construction:Rule.Construction = try input.parse(as: Rule.self) 
            input.parse(as: Padding.self, in: Void.self)
            return construction
        }
    }
}
