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

module laniakea.db.schema.isotope;
@safe:

import laniakea.db.schema.jobs;
import laniakea.db.schema.core;


/**
 * Instructions on how to do an automatic ISO image build.
 */
struct ImageBuildRecipe {
    UUID uuid;              /// Laniakea object ID

    string name;            /// A unique name identifying this recipe
    string distribution;    /// Name of the distribution, e.g. "Tanglu"
    string suite;           /// Suite of the distribution to build an image for
    string flavor;          /// The flavor to build
    string[] architectures; /// Architectures to build the image for

    string liveBuildGit;    /// Git repository URL with the live-build scripts
    string resultMoveTo;    /// Local or remote URL to copy the resulting build artifacts to


    this (ResultSet r) @trusted
    {
        import vibe.data.json : parseJsonString, deserializeJson;
        import laniakea.utils : safeParseUUID;
        assert (r.getMetaData.getColumnCount == 8);

        uuid          = safeParseUUID (r.getString (1));
        name          = r.getString (2);
        distribution  = r.getString (3);
        suite         = r.getString (4);
        flavor        = r.getString (5);
        architectures = deserializeJson!(string[]) (r.getString (6));

        liveBuildGit  = r.getString (7);
        resultMoveTo  = r.getString (8);
    }
}


import laniakea.db.database;

/**
 * Create initial tables for this module.
 */
void createTables (Database db) @trusted
{
    auto conn = db.getConnection ();
    scope (exit) db.dropConnection (conn);
    auto stmt = conn.createStatement();
    scope(exit) stmt.close();

    stmt.executeUpdate (
        "CREATE TABLE IF NOT EXISTS isotope_recipes (
          uuid             UUID PRIMARY KEY,
          name             TEXT NOT NULL UNIQUE,
          distribution     TEXT NOT NULL,
          suite            TEXT NOT NULL,
          flavor           TEXT,
          architectures    JSONB,
          livebuild_git    TEXT NOT NULL,
          result_move_to   TEXT
        )"
    );
}

/**
 * Add/update image build recipe.
 */
void update (Connection conn, ImageBuildRecipe recipe) @trusted
{
    import vibe.data.json : serializeToJsonString;

    immutable sql = "INSERT INTO isotope_recipes
                    VALUES (?,
                            ?,
                            ?,
                            ?,
                            ?,
                            ?::jsonb,
                            ?,
                            ?
                        )
                    ON CONFLICT (uuid) DO UPDATE SET
                      name           = ?,
                      distribution   = ?,
                      suite          = ?,
                      flavor         = ?,
                      architectures  = ?::jsonb,
                      livebuild_git  = ?,
                      result_move_to = ?";

    auto ps = conn.prepareStatement (sql);
    scope (exit) ps.close ();

    ps.setString (1, recipe.uuid.toString);
    ps.setString (2, recipe.name);
    ps.setString (3, recipe.distribution);
    ps.setString (4, recipe.suite);
    ps.setString (5, recipe.flavor);
    ps.setString (6, recipe.architectures.serializeToJsonString);
    ps.setString (7, recipe.liveBuildGit);
    ps.setString (8, recipe.resultMoveTo);

    ps.setString (9, recipe.name);
    ps.setString (10, recipe.distribution);
    ps.setString (11, recipe.suite);
    ps.setString (12, recipe.flavor);
    ps.setString (13, recipe.architectures.serializeToJsonString);
    ps.setString (14, recipe.liveBuildGit);
    ps.setString (15, recipe.resultMoveTo);

    ps.executeUpdate ();
}

auto getBuildRecipes (Connection conn, long limit, long offset = 0) @trusted
{
    auto ps = conn.prepareStatement ("SELECT * FROM isotope_recipes ORDER BY name LIMIT ? OFFSET ?");
    scope (exit) ps.close ();

    ps.setLong (2, offset);
    if (limit > 0)
        ps.setLong  (1, limit);
    else
        ps.setLong  (1, long.max);

    auto ans = ps.executeQuery ();
    return rowsTo!ImageBuildRecipe (ans);
}

auto getRecipeByName (Connection conn, string name) @trusted
{
    auto ps = conn.prepareStatement ("SELECT * FROM isotope_recipes WHERE name=?");
    scope (exit) ps.close ();

    ps.setString (1, name);

    auto ans = ps.executeQuery ();
    return rowsToOne!ImageBuildRecipe (ans);
}

auto getRecipeById (Connection conn, UUID uuid) @trusted
{
    auto ps = conn.prepareStatement ("SELECT * FROM isotope_recipes WHERE uuid=?");
    scope (exit) ps.close ();

    ps.setString (1, uuid.toString);

    auto ans = ps.executeQuery ();
    return rowsToOne!ImageBuildRecipe (ans);
}
