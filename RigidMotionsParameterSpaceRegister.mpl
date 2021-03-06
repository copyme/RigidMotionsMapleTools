# Class: ComputationRegister
#
# Description:
#  This class implements a register of the computations (see
#  RigidMotionsParameterSpaceDecompostion) which is based on SQLite.
#  Thanks to the register the computations can be restored after a crash.
#
# Author:
#  Kacper Pluta - kacper.pluta@esiee.fr
#  Laboratoire d'Informatique Gaspard-Monge - LIGM, A3SI, France
#
# Date:
#  11/12/2016 
#
# License:
#  Simplified BSD License
#
# Copyright (c) 2016, Kacper Pluta
# All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL Kacper Pluta BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
module ComputationRegister()
  option object;
  
  (* Connection object returned by Database[SQLite]:-Open *)
  local connection;
  local version;

# Comments:
#  We should use Database[SQLite]:-Bind() with care. Values passed should be given as local or
#  global but never as values returned from other procedures.

# Method: ModuleCopy
#   Standard constructor / copy constructor
#
# Parameters:
#   self::ComputationRegister      - a new object to be constructed
#   proto::ComputationRegister     - a prototype object from which self is derived
#   dbPath::string                 - a path to a database
#
# Comment:
#   The database is open in such a way that journal_mode is set to WAL and
#   synchronous to NORMAL. These option should not be changed! 
#   See SQLite documentation for more information. Note that second database
#   is created in memory to speed up inserts. In particular, small chunks of
#   data are first inserted into the memory database and then moved in one
#   transaction into the main database.
#
# Output:
#   An object of type ComputationRegister.
#
# Exceptions:
#  "There is no database" occurs when a given file (dbPath) does not exists.
# 
  export ModuleCopy::static := proc( self::ComputationRegister,
                                     proto::ComputationRegister,
                                     dbPath::string, $ )
  local fileStatus := false, version, stmt, openStatus := true;
    if _passed = 2 then
      self:-connection := proto:-connection;
      self:-version := proto:-version;
    else
      fileStatus:=FileTools:-Exists(dbPath);
      # wait until DB is not busy
      while openStatus do
        try
          openStatus := false;
          self:-connection := Database[SQLite]:-Open(dbPath);
        catch "database is locked":
          openStatus := true;
        end try;
      od;
      Database[SQLite]:-Attach(self:-connection, ":memory:", "cacheDB");
      Database[SQLite]:-Execute(self:-connection, "PRAGMA synchronous = NORMAL;");
      Database[SQLite]:-Execute(self:-connection, "PRAGMA journal_mode = WAL;");
      Database[SQLite]:-Execute(self:-connection, "PRAGMA cacheDB.auto_vacuum = FULL;");

      #Create tables
      if not fileStatus then
        Database[SQLite]:-Execute(self:-connection,"CREATE TABLE Quadric (ID PRIMARY KEY NOT " ||
        "NULL UNIQUE, polynom TEXT NOT NULL UNIQUE check(length(polynom) > 0));");
        Database[SQLite]:-Execute(self:-connection,"CREATE TABLE RealAlgebraicNumber (ID " ||
        "INTEGER PRIMARY KEY UNIQUE, polynom TEXT NOT NULL check(length(polynom) > 0), " ||
        "IntervalL TEXT NOT NULL check(length(IntervalL) > 0), IntervalR " ||
        "TEXT NOT NULL check(length(IntervalR) > 0));");
        Database[SQLite]:-Execute(self:-connection,"CREATE TABLE Events (RANumID INTEGER " ||
        "REFERENCES RealAlgebraicNumber (ID) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL, " ||
        "QuadID INTEGER REFERENCES Quadric (ID) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL);");
        Database[SQLite]:-Execute(self:-connection,"CREATE TABLE SamplePoint (A TEXT NOT NULL " ||
        "check(length(A) > 0), B TEXT NOT NULL check(length(B) > 0), C TEXT NOT NULL " ||
        "check(length(C) > 0));");
        Database[SQLite]:-Execute(self:-connection, "CREATE TABLE ComputedNumbers (RANumID " ||
        "INTEGER REFERENCES RealAlgebraicNumber (ID) ON DELETE CASCADE ON UPDATE CASCADE NOT " ||
        "NULL);");
      fi;

      stmt := Database[SQLite]:-Prepare(self:-connection, "PRAGMA user_version;");
      while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
      self:-version := Database[SQLite]:-Fetch(stmt, 0);
      Database[SQLite]:-Finalize(stmt);

      if self:-version = 0 then
        Database[SQLite]:-Execute(self:-connection,"CREATE TABLE cacheDB.RealAlgebraicNumber (ID " ||
        "INTEGER PRIMARY KEY UNIQUE, polynom TEXT NOT NULL check(length(polynom) > 0), " ||
        "IntervalL TEXT NOT NULL check(length(IntervalL) > 0), IntervalR TEXT NOT NULL " ||
        "check(length(IntervalR) > 0));");
        Database[SQLite]:-Execute(self:-connection, "CREATE TABLE cacheDB.Quadric (ID PRIMARY KEY " ||
        "NOT NULL UNIQUE, polynom TEXT NOT NULL UNIQUE check(length(polynom) > 0));");
        Database[SQLite]:-Execute(self:-connection, "CREATE TABLE cacheDB.Events (RANumID INTEGER " ||
        "REFERENCES RealAlgebraicNumber (ID) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL, " ||
        "QuadID INTEGER REFERENCES Quadric (ID) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL);");
        Database[SQLite]:-Execute(self:-connection, "CREATE TABLE cacheDB.SamplePoint (" ||
        "A TEXT NOT NULL check(length(A) > 0), B TEXT NOT NULL check(length(B) > 0), C TEXT " ||
        "NOT NULL check(length(C) > 0));");
      elif self:-version = 1 then
        Database[SQLite]:-Execute(self:-connection,"CREATE TABLE cacheDB.SamplePointSignature " ||
        "(SP_ID NOT NULL, Signature TEXT NOT NULL UNIQUE check(length(Signature) > 0));");
      elif self:-version >= 2 then
        Database[SQLite]:-Execute(self:-connection, "CREATE TABLE cacheDB.NMM (NMM TEXT NOT NULL " ||
        "UNIQUE check(length(NMM) > 0), SP_ID NOT NULL, T1 TEXT NOT NULL " ||
        "check(length(T1) > 0), T2 TEXT NOT NULL check(length(T2) > 0), T3 TEXT NOT NULL " ||
        "check(length(T3) > 0));");
      fi;
    fi;
    return self;
  end proc;


  export Close::static := proc( self::ComputationRegister )
    Database[SQLite]:-Close(self:-connection);
  end proc;

  
  export DatabaseVersion::static := proc( self::ComputationRegister )
    return self:-version;
  end proc;


# Method: ModulePrint
#   Standard printout of an object of type ComputationRegister.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
  export ModulePrint::static := proc( self::ComputationRegister )
    print(self:-connection);
  end proc;

# Method: InsertQuadric
#   Used to insert quadrics into a database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#   id::integer                    - an identifier of a given quadric
#   quadric::polynom               - a second degree polynomial
#
# Comments:
#   Each quadric is inserted into a cache, memory stored, database.
#   SynchronizeQuadrics has to be called to move inserted polynomials
#   into the register.
#
  export InsertQuadric::static := proc(self::ComputationRegister, id::integer, quadric::polynom)
    local stmt, poly := sprintf("%a", quadric);
    if self:-version > 0 then
      error "Adding new quadrics is blocked! Re-run computations with a new database.";
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT OR IGNORE INTO " ||
                                 "cacheDB.Quadric(ID, polynom) VALUES (?, ?);");
    Database[SQLite]:-Bind(stmt, 1, id);
    Database[SQLite]:-Bind(stmt, 2, poly);
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);
  end proc;


# Method: InsertEvent
#   Used to insert quadrics into a database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#   idNum::integer                 - an identifier of a given event
#   event::EventType               - a given event
# Comments:
#   Each event is inserted into a cache, memory stored, database.
#   SynchronizeEvents has to be called to move inserted events
#   into the register.
#
  export InsertEvent::static := proc(self::ComputationRegister, idNum::integer,
                                     event::EventType)
    local x::integer, num, quadrics, stmt, poly, interA, interB;
    if self:-version > 0 then
      error "Adding new events is blocked! Re-run computations with a new database.";
    fi;
    num := GetRealAlgebraicNumber(event); quadrics := GetQuadrics(event);
    poly := sprintf("%a", GetPolynomial(num));
    interA := sprintf("%a", GetInterval(num)[1]);
    interB := sprintf("%a", GetInterval(num)[2]);
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT OR IGNORE INTO " ||
            "cacheDB.RealAlgebraicNumber(ID, polynom, IntervalL, IntervalR) " ||
                                             "VALUES (?, ?, ?, ?);");
    Database[SQLite]:-Bind(stmt, 1, idNum);
    Database[SQLite]:-Bind(stmt, 2, poly);
    Database[SQLite]:-Bind(stmt, 3, interA);
    Database[SQLite]:-Bind(stmt, 4, interB);

    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);

    for x in quadrics do
      stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT OR IGNORE INTO " ||
                             "cacheDB.Events(RANumID, QuadID) VALUES(?, ?);");
      Database[SQLite]:-Bind(stmt, 1, idNum);
      Database[SQLite]:-Bind(stmt, 2, x);
     while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
     Database[SQLite]:-Finalize(stmt);
    od;
  end proc;


# Method: InsertSignature
#   Used to insert unique signatures of rotational sample points into a database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#   id::integer                    - an identifier of a given rotational sample point
#   sig::string                    - a given signature -- ordered indices of the critical planes
#
  export InsertSignature::static := proc(self::ComputationRegister, id::integer, sig::string)
    local stmt;
    if self:-version <> 1 then
      return NULL;
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT OR IGNORE INTO " ||
            "cacheDB.SamplePointSignature(SP_ID, Signature) VALUES (?, ?);");
    Database[SQLite]:-Bind(stmt, 1, id);
    Database[SQLite]:-Bind(stmt, 2, sig);

    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);
  end proc;


# Method: SynchronizeSamplePointsSignatures
#   Used to synchronize a cache database with the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
  export SynchronizeSamplePointsSignatures::static := proc(self::ComputationRegister)
    local stmt;
    if self:-version <> 1 then
      return NULL;
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT INTO SamplePointSignature " || 
            "(SP_ID, Signature) SELECT * FROM cacheDB.SamplePointSignature AS SC WHERE NOT " ||
            "EXISTS(SELECT 1 FROM SamplePointSignature AS S WHERE SC.Signature = S.Signature);");
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);

    #clean up cacheDB
    stmt := Database[SQLite]:-Execute(self:-connection,"DELETE FROM cacheDB.SamplePointSignature;");
end proc;


# Method: CloseSignaturesAddition
#   Used to mark that signatures were computed.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
  export CloseSignaturesAddition::static := proc(self::ComputationRegister)
    if self:-version <> 1 then
      return NULL;
    fi;

    Database[SQLite]:-Execute(self:-connection, "PRAGMA user_version = 2;");
    self:-version := 2;
end proc;


# Method: InsertNMM
#   Used to insert a nieghborhood motion map into the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#   ID::integer                    - an id of the rotational sample point
#   NMM::list                      - a list of lists which represent a neighborhood motion map
#   T::list                        - a list or rationals which represent a translational sample
#                                    point
#
  export InsertNMM::static := proc(self::ComputationRegister, ID::integer, NMM::list, T::list)
    local stmt, NMMString, transX, transY, transZ;
    if self:-version < 2 then
      return NULL;
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT OR IGNORE INTO " ||
                                             "cacheDB.NMM(SP_ID, NMM, T1, T2, T3) VALUES (?, ?, " ||
                                             "?, ?, ?);");
    NMMString := sprintf("%a", NMM); transX := sprintf("%a", T[1]); transY := sprintf("%a", T[2]);
    transZ := sprintf("%a", T[3]);
    Database[SQLite]:-Bind(stmt, 1, ID);
    Database[SQLite]:-Bind(stmt, 2, NMMString);
    Database[SQLite]:-Bind(stmt, 3, transX);
    Database[SQLite]:-Bind(stmt, 4, transY);
    Database[SQLite]:-Bind(stmt, 5, transZ);

    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);
  end proc;



# Method: SynchronizeNMM
#   Used to synchronize a cache database with the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
  export SynchronizeNMM::static := proc(self::ComputationRegister)
    local stmt;
    if self:-version < 2 then
      return NULL;
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT INTO NMM (NMM, SP_ID, T1, T2, " ||
            "T3) SELECT * FROM cacheDB.NMM AS CNM WHERE NOT EXISTS(SELECT 1 FROM NMM AS NM " ||
                                                                     "WHERE NM.NMM = CNM.NMM);");
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);

    #clean up cacheDB
    stmt := Database[SQLite]:-Execute(self:-connection,"DELETE FROM cacheDB.NMM;");
  end proc;


# Method: SynchronizeQuadrics
#   Synchronize quadrics between memory, cache, database and a given database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
#
  export SynchronizeQuadrics::static := proc(self::ComputationRegister)
    local stmt;
    if self:-version > 0 then
      return NULL;
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT INTO Quadric SELECT * FROM " ||
            "cacheDB.Quadric as qc WHERE NOT EXISTS(SELECT 1 FROM Quadric AS Q WHERE " ||
                                                           "q.POLYNOM = qc.POLYNOM);");
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);
  end proc;


# Method: SynchronizeEvents
#   Synchronize events between memory, cache, database and a given database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
# Comments:
#   Cache database is cleared. Therefore, the method should be called only when all events were
#   inserted.
  export SynchronizeEvents::static := proc(self::ComputationRegister)
    local stmt;
    if self:-version > 0 then
      return NULL;
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT INTO RealAlgebraicNumber " ||
                                "SELECT * FROM cacheDB.RealAlgebraicNumber AS rc WHERE NOT " ||
                                "EXISTS(SELECT 1 FROM RealAlgebraicNumber AS R WHERE " ||
                                "r.ID = rc.ID AND r.POLYNOM = rc.POLYNOM AND " ||
                                "r.INTERVALL = rc.INTERVALL AND " ||
                                "r.INTERVALR = rc.INTERVALR);");
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);

    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT INTO Events SELECT * FROM " ||
                           "cacheDB.Events AS ev WHERE NOT EXISTS( SELECT 1 FROM Events AS E " ||
                           "WHERE e.RANUMID = ev.RANUMID AND e.QUADID = ev.QUADID);");
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);

    #clean up cacheDB
    stmt := Database[SQLite]:-Execute(self:-connection,"DELETE FROM cacheDB.RealAlgebraicNumber;");
  end proc;


# Method: InsertComputedNumber
#    Inserts ids' of computed events into a given database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#   id::integer                    - an integer which stands for the identifier of a cluster
#
#
  export InsertComputedNumber::static := proc(self::ComputationRegister, id::integer)
    local stmt;
    if self:-version > 0 then
      error "Adding new computed events is blocked! Re-run computations with a new database.";
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT OR IGNORE INTO " ||
                                 "ComputedNumbers (RANumID) VALUES (?);");
    Database[SQLite]:-Bind(stmt, 1, id);    
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);
  end proc;


# Method: InsertSamplePoint
#    Inserts a sample point into a given database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#   samp::list                     - a list of three rational numbers which represent a sample point
#
#
  export InsertSamplePoint::static := proc(self::ComputationRegister, samp::list)
    local stmt, a, b, c;
    if self:-version > 0 then
      error "Adding new computed sample points is blocked! Re-run computations with a new database.";
    fi;
    a := sprintf("%a", samp[1]); b := sprintf("%a", samp[2]); c := sprintf("%a", samp[3]);
    stmt := Database[SQLite]:-Prepare(self:-connection,"INSERT INTO cacheDB.SamplePoint " ||
                                                       "(A, B, C) VALUES (?, ?, ?);");
    Database[SQLite]:-Bind(stmt, 1, a);
    Database[SQLite]:-Bind(stmt, 2, b);
    Database[SQLite]:-Bind(stmt, 3, c);

    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);
  end proc;


# Method: SynchronizeSamplePoints
#    Synchronize sample points between cache, memory, database and a given database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
# Comments:
#   Cache database is cleared.
  export SynchronizeSamplePoints::static := proc(self::ComputationRegister)
    local stmt;
    if self:-version > 0 then
      return NULL;
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection, "INSERT INTO SamplePoint SELECT * " ||
                                                                 "FROM cacheDB.SamplePoint;");
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    Database[SQLite]:-Finalize(stmt);

    #clean up cacheDB
    stmt := Database[SQLite]:-Execute(self:-connection,"DELETE FROM cacheDB.SamplePoint;");
  end proc;


# Method: FetchComputedNumbers
#    Fetch ids' of events which were processed already from the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
#
# Output:
#   A list of integers.
#
  export FetchComputedNumbers::static := proc(self::ComputationRegister)
    local stmt := Database[SQLite]:-Prepare(self:-connection, "SELECT * FROM ComputedNumbers;");
    local result := convert(Database[SQLite]:-FetchAll(stmt), list);
    Database[SQLite]:-Finalize(stmt);
    return result;
  end proc;


# Method: FetchQuadrics
#    Fetch quadrics from the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
#
# Output:
#   A list of second degree polynomials.
#
  export FetchQuadrics::static := proc(self::ComputationRegister)
    local stmt := Database[SQLite]:-Prepare(self:-connection, "SELECT polynom FROM Quadric " ||
                                            "ORDER BY ID;");
    local result := map(parse, convert(Database[SQLite]:-FetchAll(stmt), list));
    Database[SQLite]:-Finalize(stmt);
    return result;
  end proc;


export FetchLowerEventID := proc(self::ComputationRegister)
    local lowerID;
    local stmt := Database[SQLite]:-Prepare(self:-connection, "SELECT MIN(ID) FROM RealAlgebraicNumber;");
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    lowerID := Database[SQLite]:-Fetch(stmt, 0);
    Database[SQLite]:-Finalize(stmt);
    return lowerID;
end proc;

# Method: FetchEvents
#    Fetch events from the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#   first::integer                 - an id of the first event from a given range
#   last::integer                  - an id of the last event from a given range
#
#
# Output:
#   An Array of EventType.
#
  export FetchEvents::static := proc(self::ComputationRegister, first::integer, last::integer)
    local row, events:=Array([]);
    local stmt := Database[SQLite]:-Prepare(self:-connection, "SELECT ID, polynom, IntervalL, " ||
    "IntervalR, group_concat(QuadID) FROM RealAlgebraicNumber JOIN EVENTS " ||
    "ON ID = RANUMID WHERE ID BETWEEN ? AND ? GROUP BY ID ORDER BY ID;"); 
    Database[SQLite]:-Bind(stmt, 1, first);
    Database[SQLite]:-Bind(stmt, 2, last);

    #Slow but Fetching all can kill with memory consumption
    while Database[SQLite]:-Step(stmt) <> Database[SQLite]:-RESULT_DONE do
      row := Database[SQLite]:-FetchRow(stmt);
      events(row[1]) := EventType(RealAlgebraicNumber(parse(row[2]), parse(row[3]), 
                    parse(row[4])), [parse(row[5])]);
    od;
    Database[SQLite]:-Finalize(stmt);
    return events;
  end proc;


# Method: FetchSamplePointsWithoutSignature
#   Used to fetch a given number of sample points from the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#   first::integer                 - an id of a sample point which represent the beginning of the
#                                    range of ids to be fetched
#   last::integer                  - an id of a sample point which represent the end of the range of
#                                    ids to be fetched
# Comment:
#   Only sample points without signatures are fetch.
#
  export FetchSamplePointsWithoutSignature::static := proc(self::ComputationRegister, 
                                                       first::integer, last::integer)
    local row, buffer:=Array([]), stmt;
     if self:-version < 1 then
      error "This version of FetchSamplePoints requires a database in version 1.";
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection, "SELECT ID, A, B, C FROM SamplePoint AS S " ||
            "WHERE S.ID BETWEEN ? AND ? AND NOT EXISTS( SELECT 1 FROM SamplePointSignature AS SS " ||
                                                                         "WHERE S.ID = SS.SP_ID);"); 
    Database[SQLite]:-Bind(stmt, 1, first);
    Database[SQLite]:-Bind(stmt, 2, last);

    #Slow but Fetching all can kill with memory consumption
    while Database[SQLite]:-Step(stmt) <> Database[SQLite]:-RESULT_DONE do
      row := Database[SQLite]:-FetchRow(stmt);
      ArrayTools:-Append(buffer, [row[1], op(map(parse, row[2..()]))], inplace=true);
    od;
    Database[SQLite]:-Finalize(stmt);
    return buffer;
  end proc;


# Method: FetchTopologicallyDistinctSamplePoints
#   Used to fetch a given number of topologically different sample points from the database. These
#   are the sample points which induce different order of the critical planes in the remainder range
#   -- they have different signatures.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#   first::integer                 - an id of a sample point which represent the beginning of the
#                                    range of ids to be fetched
#   last::integer                  - an id of a sample point which represent the end of the range of
#                                    ids to be fetched
#
  export FetchTopologicallyDistinctSamplePoints::static := proc(self::ComputationRegister, 
                                                            first::integer, last::integer)
    local row, buffer:=Array([]), stmt;
     if self:-version < 1 then
      error "This version of FetchTopologicallyDistinctSamplePoints requires a database " ||
            "in version 1.";
    fi;
    stmt := Database[SQLite]:-Prepare(self:-connection, "SELECT S.ID, A, B, C FROM " ||
    "SamplePoint AS S, SamplePointSignature AS SSP WHERE S.ID = SSP.SP_ID AND SSP.ID " ||
    "BETWEEN ? AND ?;"); 
    Database[SQLite]:-Bind(stmt, 1, first);
    Database[SQLite]:-Bind(stmt, 2, last);

    #Slow but Fetching all can kill with memory consumption
    while Database[SQLite]:-Step(stmt) <> Database[SQLite]:-RESULT_DONE do
      row := Database[SQLite]:-FetchRow(stmt);
      ArrayTools:-Append(buffer, [row[1], op(map(parse, row[2..()]))], inplace=true);
    od;
    Database[SQLite]:-Finalize(stmt);
    return buffer;
  end proc;


# Method: NumberOfEvents
#   Returns number of events in the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
# Output:
#   Number of events in the database.
#
  export NumberOfEvents::static := proc(self::ComputationRegister)
    local stmt, num;
    stmt := Database[SQLite]:-Prepare(self:-connection, "SELECT COUNT(ID) " ||
                                            "FROM RealAlgebraicNumber;"); 
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    num := Database[SQLite]:-Fetch(stmt, 0);
    Database[SQLite]:-Finalize(stmt);
    return num;
  end proc;
  

# Method: NumberOfEvents
#   Updates the database from version 0 into 1 by adding tables which stores neighborhood motion
#   maps, translational sample points and signatures of rotational sample points. After the updated
#   it is not possible to add new events or rotational sample points into the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
  export PrepareSamplePoints::static := proc(self::ComputationRegister)
    local stmt, toCompute;
    stmt := Database[SQLite]:-Prepare(self:-connection,"SELECT COUNT(ID) FROM RealAlgebraicNumber "
    || "WHERE ID NOT IN (SELECT RANUMID FROM ComputedNumbers) AND ID NOT IN (SELECT MAX(ID) " ||
    "FROM RealAlgebraicNumber);"); 
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    toCompute := Database[SQLite]:-Fetch(stmt, 0);
    Database[SQLite]:-Finalize(stmt);

    if self:-version = 0 and toCompute = 0 then
      Database[SQLite]:-Execute(self:-connection, "ALTER TABLE SamplePoint RENAME TO " || 
      "sqlitestudio_temp_table; CREATE TABLE SamplePoint (A TEXT NOT NULL check(length(A) > 0), " ||
      "B TEXT NOT NULL check(length(B) > 0), C TEXT NOT NULL check(length(C) > 0), " ||
      "ID INTEGER PRIMARY KEY AUTOINCREMENT); INSERT INTO SamplePoint (A, B, C) SELECT A, B, C " ||
      "FROM sqlitestudio_temp_table; DROP TABLE sqlitestudio_temp_table;");
      Database[SQLite]:-Execute(self:-connection, "PRAGMA user_version = 1;");
      self:-version := 1;
      Database[SQLite]:-Execute(self:-connection, "CREATE TABLE SamplePointSignature (ID INTEGER " ||
      "PRIMARY KEY AUTOINCREMENT, SP_ID REFERENCES SamplePoint (ID) ON DELETE CASCADE ON UPDATE " ||
      "CASCADE NOT NULL, Signature TEXT NOT NULL UNIQUE check(length(Signature) > 0));");
      Database[SQLite]:-Execute(self:-connection, "CREATE TABLE cacheDB.SamplePointSignature " ||
      "(SP_ID NOT NULL, Signature TEXT NOT NULL UNIQUE check(length(Signature) > 0));"); 
      Database[SQLite]:-Execute(self:-connection,"CREATE TABLE NMM (ID INTEGER PRIMARY KEY " ||
      "AUTOINCREMENT, NMM TEXT NOT NULL UNIQUE check(length(NMM) > 0), SP_ID INTEGER " ||
      "REFERENCES SamplePoint (ID) ON DELETE CASCADE ON UPDATE CASCADE, T1 TEXT NOT NULL " ||
      "check(length(T1) > 0), T2 TEXT NOT NULL check(length(T2) > 0), T3 TEXT NOT NULL " ||
      "check(length(T3) > 0));");
      Database[SQLite]:-Execute(self:-connection,"CREATE TABLE cacheDB.NMM (NMM TEXT NOT NULL " ||
      "UNIQUE check(length(NMM) > 0), SP_ID NOT NULL, T1 TEXT NOT NULL check(length(T1) > 0), " ||
      "T2 TEXT NOT NULL check(length(T2) > 0), T3 TEXT NOT NULL check(length(T3) > 0));");
    elif toCompute <> 0 then
      Close(self);
      error "Before running computation of NMM it is necessary to compute all sample points! " ||
      "Please, run first RigidMotionsParameterSpaceDecompostion:-LaunchResumeComputations().";
    fi;
  end proc;


# Method: NumberOfSamplePoints
#   Returns number of the rotational sample points in the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
# Output:
#   Number of the rotational sample points in the database.
#
  export NumberOfSamplePoints::static := proc(self::ComputationRegister)
    local stmt, num::integer;
    stmt := Database[SQLite]:-Prepare(self:-connection, "SELECT COUNT(*) FROM SamplePoint;"); 
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    num::integer := Database[SQLite]:-Fetch(stmt, 0);
    Database[SQLite]:-Finalize(stmt);
    return num;
  end proc;


# Method: NumberOfTopologicallyDistinctSamplePoints
#   Returns number of the topologically distinct rotational sample points in the database.
#
# Parameters:
#   self::ComputationRegister      - an instance of ComputationRegister
#
# Output:
#   Number of the topologically distinct sample points in the database.
#
  export NumberOfTopologicallyDistinctSamplePoints::static := proc(self::ComputationRegister)
    local stmt, num::integer;
    stmt := Database[SQLite]:-Prepare(self:-connection, "SELECT COUNT(*) FROM SamplePoint AS S, " ||
               "SamplePointSignature AS SSP WHERE S.ID = SSP.SP_ID;"); 
    while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
    num::integer := Database[SQLite]:-Fetch(stmt, 0);
    Database[SQLite]:-Finalize(stmt);
    return num;
  end proc;
  

  export DropRedundantSamplePoints::static := proc(self::ComputationRegister)
    local stmt;
    if self:-version = 2 then
      Database[SQLite]:-Execute(self:-connection, "CREATE TABLE SamplePoints (A TEXT NOT NULL " || 
      "CHECK (length(A) > 0), B TEXT NOT NULL CHECK (length(B) > 0), C TEXT NOT NULL CHECK " || 
      "(length(C) > 0), ID INTEGER PRIMARY KEY);");

      # Copy only topologically unique sample points
      stmt := Database[SQLite]:-Prepare(self:-connection, "INSERT INTO SamplePoints SELECT A, B," ||
      "C, S.ID FROM SamplePoint AS S, SamplePointSignature AS SSP WHERE S.ID = SSP.SP_ID;");
      while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
      Database[SQLite]:-Finalize(stmt);


      Database[SQLite]:-Execute(self:-connection, "CREATE TABLE SamplePointSignatures (ID INTEGER "
      || "PRIMARY KEY AUTOINCREMENT, SP_ID REFERENCES SamplePoints (ID) ON DELETE CASCADE ON " || 
      "UPDATE CASCADE NOT NULL, Signature TEXT NOT NULL UNIQUE CHECK (length(Signature) > 0));");

      # Copy data 
      stmt := Database[SQLite]:-Prepare(self:-connection, "INSERT INTO SamplePointSignatures "|| 
      "SELECT * FROM SamplePointSignature;");
      while Database[SQLite]:-Step(stmt) = Database[SQLite]:-RESULT_BUSY do; od;
      Database[SQLite]:-Finalize(stmt);

      Database[SQLite]:-Execute(self:-connection, "DROP TABLE SamplePointSignature; " ||
      "DROP TABLE SamplePoint; VACUUM;");

     # Recover old names
     Database[SQLite]:-Execute(self:-connection, "ALTER TABLE SamplePoints RENAME TO " || 
     "SamplePoint;");

     Database[SQLite]:-Execute(self:-connection, "ALTER TABLE SamplePointSignatures RENAME TO " || 
     "SamplePointSignature;");

      Database[SQLite]:-Execute(self:-connection, "PRAGMA user_version = 3;");
      self:-version := 3;
    fi;
  end proc;
end module;

