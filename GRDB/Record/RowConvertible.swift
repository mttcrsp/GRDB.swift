#if SWIFT_PACKAGE
    import CSQLite
#elseif !GRDBCUSTOMSQLITE && !GRDBCIPHER
    import SQLite3
#endif

/// Types that adopt RowConvertible can be initialized from a database Row.
///
///     let row = try Row.fetchOne(db, "SELECT ...")!
///     let player = Player(row)
///
/// The protocol comes with built-in methods that allow to fetch cursors,
/// arrays, or single records:
///
///     try Player.fetchCursor(db, "SELECT ...", arguments:...) // Cursor of Player
///     try Player.fetchAll(db, "SELECT ...", arguments:...)    // [Player]
///     try Player.fetchOne(db, "SELECT ...", arguments:...)    // Player?
///
///     let statement = try db.makeSelectStatement("SELECT ...")
///     try Player.fetchCursor(statement, arguments:...) // Cursor of Player
///     try Player.fetchAll(statement, arguments:...)    // [Player]
///     try Player.fetchOne(statement, arguments:...)    // Player?
///
/// RowConvertible is adopted by Record.
public protocol RowConvertible {
    
    /// Creates a record from `row`.
    ///
    /// For performance reasons, the row argument may be reused during the
    /// iteration of a fetch query. If you want to keep the row for later use,
    /// make sure to store a copy: `self.row = row.copy()`.
    init(row: Row)
}

/// A cursor of records. For example:
///
///     struct Player : RowConvertible { ... }
///     try dbQueue.inDatabase { db in
///         let players: RecordCursor<Player> = try Player.fetchCursor(db, "SELECT * FROM players")
///     }
public final class RecordCursor<Record: RowConvertible> : Cursor {
    private let statement: SelectStatement
    private let row: Row // Reused for performance
    private let sqliteStatement: SQLiteStatement
    private var done = false
    
    init(statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws {
        self.statement = statement
        self.row = try Row(statement: statement).adapted(with: adapter, layout: statement)
        self.sqliteStatement = statement.sqliteStatement
        statement.cursorReset(arguments: arguments)
    }
    
    /// :nodoc:
    public func next() throws -> Record? {
        if done { return nil }
        switch sqlite3_step(sqliteStatement) {
        case SQLITE_DONE:
            done = true
            return nil
        case SQLITE_ROW:
            return Record(row: row)
        case let code:
            statement.database.selectStatementDidFail(statement)
            throw DatabaseError(resultCode: code, message: statement.database.lastErrorMessage, sql: statement.sql, arguments: statement.arguments)
        }
    }
}

extension RowConvertible {
    
    // MARK: Fetching From SelectStatement
    
    /// A cursor over records fetched from a prepared statement.
    ///
    ///     let statement = try db.makeSelectStatement("SELECT * FROM players")
    ///     let players = try Player.fetchCursor(statement) // Cursor of Player
    ///     while let player = try players.next() { // Player
    ///         ...
    ///     }
    ///
    /// If the database is modified during the cursor iteration, the remaining
    /// elements are undefined.
    ///
    /// The cursor must be iterated in a protected dispath queue.
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A cursor over fetched records.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchCursor(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> RecordCursor<Self> {
        return try RecordCursor(statement: statement, arguments: arguments, adapter: adapter)
    }
    
    /// Returns an array of records fetched from a prepared statement.
    ///
    ///     let statement = try db.makeSelectStatement("SELECT * FROM players")
    ///     let players = try Player.fetchAll(statement) // [Player]
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array of records.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchAll(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> [Self] {
        return try Array(fetchCursor(statement, arguments: arguments, adapter: adapter))
    }
    
    /// Returns a single record fetched from a prepared statement.
    ///
    ///     let statement = try db.makeSelectStatement("SELECT * FROM players")
    ///     let player = try Player.fetchOne(statement) // Player?
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An optional record.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchOne(_ statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> Self? {
        return try fetchCursor(statement, arguments: arguments, adapter: adapter).next()
    }
}

extension RowConvertible {
    
    // MARK: Fetching From SQL
    
    /// Returns a cursor over records fetched from an SQL query.
    ///
    ///     let players = try Player.fetchCursor(db, "SELECT * FROM players") // Cursor of Player
    ///     while let player = try players.next() { // Player
    ///         ...
    ///     }
    ///
    /// If the database is modified during the cursor iteration, the remaining
    /// elements are undefined.
    ///
    /// The cursor must be iterated in a protected dispath queue.
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A cursor over fetched records.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchCursor(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> RecordCursor<Self> {
        return try SQLRequest<Self>(sql, arguments: arguments, adapter: adapter).fetchCursor(db)
    }
    
    /// Returns an array of records fetched from an SQL query.
    ///
    ///     let players = try Player.fetchAll(db, "SELECT * FROM players") // [Player]
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array of records.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchAll(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> [Self] {
        return try SQLRequest<Self>(sql, arguments: arguments, adapter: adapter).fetchAll(db)
    }
    
    /// Returns a single record fetched from an SQL query.
    ///
    ///     let player = try Player.fetchOne(db, "SELECT * FROM players") // Player?
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An optional record.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public static func fetchOne(_ db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) throws -> Self? {
        return try SQLRequest<Self>(sql, arguments: arguments, adapter: adapter).fetchOne(db)
    }
}

extension FetchRequest where RowDecoder: RowConvertible {
    
    // MARK: Fetching Record and RowConvertible
    
    /// A cursor over fetched records.
    ///
    ///     let request: ... // Some TypedRequest that fetches Player
    ///     let players = try request.fetchCursor(db) // Cursor of Player
    ///     while let player = try players.next() {   // Player
    ///         ...
    ///     }
    ///
    /// If the database is modified during the cursor iteration, the remaining
    /// elements are undefined.
    ///
    /// The cursor must be iterated in a protected dispath queue.
    ///
    /// - parameter db: A database connection.
    /// - returns: A cursor over fetched records.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public func fetchCursor(_ db: Database) throws -> RecordCursor<RowDecoder> {
        let (statement, adapter) = try prepare(db)
        return try RowDecoder.fetchCursor(statement, adapter: adapter)
    }
    
    /// An array of fetched records.
    ///
    ///     let request: ... // Some TypedRequest that fetches Player
    ///     let players = try request.fetchAll(db) // [Player]
    ///
    /// - parameter db: A database connection.
    /// - returns: An array of records.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public func fetchAll(_ db: Database) throws -> [RowDecoder] {
        let (statement, adapter) = try prepare(db)
        return try RowDecoder.fetchAll(statement, adapter: adapter)
    }
    
    /// The first fetched record.
    ///
    ///     let request: ... // Some TypedRequest that fetches Player
    ///     let player = try request.fetchOne(db) // Player?
    ///
    /// - parameter db: A database connection.
    /// - returns: An optional record.
    /// - throws: A DatabaseError is thrown whenever an SQLite error occurs.
    public func fetchOne(_ db: Database) throws -> RowDecoder? {
        let (statement, adapter) = try prepare(db)
        return try RowDecoder.fetchOne(statement, adapter: adapter)
    }
}

