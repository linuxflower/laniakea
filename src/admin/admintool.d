/*
 * Copyright (C) 2017 Matthias Klumpp <matthias@tenstral.net>
 *
 * Licensed under the GNU Lesser General Public License Version 3
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the license, or
 * (at your option) any later version.
 *
 * This software is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this software.  If not, see <http://www.gnu.org/licenses/>.
 */

import std.stdio;
import std.string : format;

import vibe.db.mongo.mongo;
import laniakea.db;


/**
 * Perform various administrative actions.
 */
class AdminTool
{

private:
    Database db;

    string m_currentMsg;


    final string readString ()
    {
        import std.string;
        string s;
        do {
            s = readln ();
            s = s.strip;
            if (s.empty)
                write (m_currentMsg);
        } while (s.empty);
        return s;
    }

    final string[] readList ()
    {
        import std.array : split;
        auto s = readString ();
        return s.split (" ");
    }

    final bool readBool ()
    {
        import std.string;

        auto s = readString ();
        if ((s == "y") || (s == "yes") || (s == "Y"))
            return true;
        else if ((s == "n") || (s == "no") || (s == "N"))
            return false;
        else {
            writeln ("Unknown input, assuming \"No\".");
            return false;
        }
    }

    final void writeQS (string msg)
    {
        m_currentMsg = format ("%s: ", msg);
        write (m_currentMsg);
    }

    final void writeQB (string msg)
    {
        m_currentMsg = format ("%s [y/n]: ", msg);
        write (m_currentMsg);
    }

public:

    this ()
    {
        db = Database.get ();
    }

    bool baseInit ()
    {
        writeln ("Configuring base settings for Laniakea");

        BaseConfig bconf;

        writeQS ("Name of this project");
        bconf.projectName = readString ();

        bool addSuite = true;
        while (addSuite) {
            DistroSuite suite;
            writeQS ("Adding a new suite. Please set a name");
            suite.name = readString ();

            writeQS ("List of components for suite '%s'".format (suite.name));
            suite.components = readList ();

            writeQS ("List of architectures for suite '%s'".format (suite.name));
            suite.architectures = readList ();

            bconf.suites ~= suite;

            writeQB ("Add another suite?");
            addSuite = readBool ();
        }

        writeQS ("Name of the 'incoming' suite which new packages are usually uploaded to");
        bconf.archive.incomingSuite = readString ();

        writeQS ("Name of the 'development' suite which is rolling or will become a final release");
        bconf.archive.develSuite = readString ();

        writeQS ("Distribution version tag (commonly found in package versions, e.g. 'tanglu' for OS 'Tanglu' with versions like '1.0-0tanglu1'");
        bconf.archive.distroTag = readString ();

        auto coll = db.configBase;

        bconf.id = BsonObjectID.generate ();
        coll.update (["kind": bconf.kind], bconf, UpdateFlags.upsert);

        db.fsync;
        return true;
    }

    void baseDumpConfig ()
    {
        writeln (db.configBase.findOne (["kind": BaseConfigKind.PROJECT]).serializeToPrettyJson);
    }

    bool synchrotronInit ()
    {
        writeln ("Configuring base settings for Synchrotron");

        SynchrotronConfig syconf;

        writeQS ("Name of the source distribution");
        syconf.sourceName = readString ();

        writeQS ("Source repository URL");
        syconf.source.repoUrl = readString ();

        bool addSuite = true;
        while (addSuite) {
            DistroSuite suite;
            writeQS ("Adding a new source suite. Please set a name");
            suite.name = readString ();

            writeQS ("List of components for suite '%s'".format (suite.name));
            suite.components = readList ();

            writeQS ("List of architectures for suite '%s'".format (suite.name));
            suite.architectures = readList ();

            syconf.source.suites ~= suite;

            writeQB ("Add another suite?");
            addSuite = readBool ();
        }

        writeQS ("Default source suite");
        syconf.source.defaultSuite = readString ();

        writeQB ("Enable sync?");
        syconf.syncEnabled = readBool ();

        writeQB ("Synchronize binary packages?");
        syconf.syncBinaries = readBool ();

        auto coll = db.configSynchrotron;

        syconf.id = BsonObjectID.generate ();
        coll.update (["kind": syconf.kind], syconf, UpdateFlags.upsert);

        db.fsync;
        return true;
    }

    void synchrotronDumpConfig ()
    {
        writeln (db.configSynchrotron.findOne (["kind": SynchrotronConfigKind.BASE]).serializeToPrettyJson);
        writeln ();
        writeln (db.configSynchrotron.findOne (["kind": SynchrotronConfigKind.BLACKLIST]).serializeToPrettyJson);
    }

    bool setConfValue (string moduleName, string command)
    {
        bool updateData (T) (MongoCollection coll, T selector, string setExpr)
        {
            try {
                auto json = parseJsonString ("{ " ~ setExpr ~ " }");
                coll.findAndModifyExt (selector, ["$set": json], ["new": true]);
            } catch (Exception e) {
                writeln ("Update failed: ", e);
                return false;
            }

            return true;
        }
        switch (moduleName) {
            case "base":
                auto coll = db.configBase;
                if (!updateData (coll, ["kind": BaseConfigKind.PROJECT], command))
                    return false;
                break;
            case "synchrotron":
                auto coll = db.configSynchrotron;
                if (!updateData (coll, ["kind": SynchrotronConfigKind.BASE], command))
                    return false;
                break;
            case "synchrotron.blacklist":
                auto coll = db.configSynchrotron;
                if (!updateData (coll, ["kind": SynchrotronConfigKind.BLACKLIST], command))
                    return false;
                break;
            case "spears":
                auto coll = db.configSpears;
                if (!updateData (coll, ["kind": SpearsConfigKind.BASE], command))
                    return false;
                break;
            case "eggshell":
                auto coll = db.configEggshell;
                if (!updateData (coll, ["kind": EggshellConfigKind.BASE], command))
                    return false;
                break;
            default:
                writeln ("Unknown module name: ", moduleName);
                return false;
        }

        return true;
    }

}
