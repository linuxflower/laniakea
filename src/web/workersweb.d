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

module web.workersweb;

import std.exception : enforce;
import std.conv : to;
import std.array : empty;
import vibe.core.log;
import vibe.http.router;
import vibe.http.server;
import vibe.utils.validation;
import vibe.db.mongo.mongo;
import vibe.web.web;

import laniakea.db;

import web.webconfig;

@path("/workers")
class WorkersWebService {
    GlobalInfo ginfo;

    private {
        WebConfig wconf;
        Database db;
 	}

    this (WebConfig conf)
    {
        wconf = conf;
        db = wconf.db;
        ginfo = wconf.ginfo;
    }

    @path("/")
 	void getWorkers (HTTPServerRequest req, HTTPServerResponse res)
 	{
        auto collWorkers = db.collWorkers ();
        auto workers = collWorkers.find!SparkWorker;

        render!("workers/workers.dt", ginfo, workers);
 	}

}
