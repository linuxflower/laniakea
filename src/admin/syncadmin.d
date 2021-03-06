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

module admin.syncadmin;

import std.stdio : writeln;
import std.string : format;

import laniakea.db;
import admin.admintool;


/**
 * Administrate Synchrotron.
 */
final class SyncAdmin : AdminTool
{
    @property
    override string toolId ()
    {
        return "synchrotron";
    }

    private SessionFactory sFactory;

    this ()
    {
        sFactory = db.newSessionFactory! (SyncBlacklistEntry);
    }

    override
    int run (string[] args)
    {
        immutable command = args[0];

        bool ret = true;
        switch (command) {
            case "init":
                ret = initDb ();
                break;
            case "dump":
                synchrotronDumpConfig ();
                break;
            case "blacklist-add":
                if (args.length < 3) {
                    writeln ("Invalid number of parameters: You need to specify a package to add and a reason to ignore it.");
                    return 1;
                }
                synchrotronBlacklistAdd (args[1], args[2]);
                break;
            case "blacklist-remove":
                if (args.length < 2) {
                    writeln ("Invalid number of parameters: You need to specify a package to remove.");
                    return 1;
                }
                synchrotronBlacklistRemove (args[1]);
                break;
            default:
                writeln ("The command '%s' is unknown.".format (command));
                return 1;
        }

        if (!ret)
            return 2;
        return 0;
    }

    override
    bool initDb ()
    {
        writeHeader ("Configuring base settings for Synchrotron");

        SynchrotronConfig syconf;

        writeQS ("Name of the source distribution");
        syconf.sourceName = readString ();

        writeQS ("Source repository URL");
        syconf.source.repoUrl = readString ();

        bool addSuite = true;
        while (addSuite) {
            SyncSourceSuite suite;
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

        // update database
        db.update (syconf);

        return true;
    }

    void synchrotronDumpConfig ()
    {
        writeln ("Config:");
        writeln (db.getSynchrotronConfig ().serializeToPrettyJson);
    }

    void synchrotronBlacklistAdd (string pkg, string reason)
    {
        auto session = sFactory.openSession ();
        scope (exit) session.close ();

        auto entry = session.createQuery ("FROM SyncBlacklistEntry WHERE pkgname=:name")
                            .setParameter ("name", pkg)
                            .uniqueResult!SyncBlacklistEntry;
        if (entry !is null) {
            writeNote ("Package '%s' is already in the blacklist.".format (pkg));
            return;
        }

        entry = new SyncBlacklistEntry;
        entry.pkgname = pkg;
        entry.date = currentDateTime;
        entry.reason = reason;
        session.save (entry);
    }

    void synchrotronBlacklistRemove (string pkg)
    {
        auto session = sFactory.openSession ();
        scope (exit) session.close ();

        auto entry = session.createQuery ("FROM SyncBlacklistEntry WHERE pkgname=:name")
                            .setParameter ("name", pkg)
                            .uniqueResult!SyncBlacklistEntry;
        if (entry is null) {
            writeNote ("Package '%s' is not blacklisted.".format (pkg));
            return;
        }

        session.remove (entry);
    }

}
