/*
 * Copyright (C) 2016-2018 Matthias Klumpp <matthias@tenstral.net>
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

module synchrotron.syncengine;

import std.array : empty;
import std.string : endsWith, startsWith, format;
import std.algorithm : canFind;
import std.array : appender;
import std.parallelism : parallel;
import std.typecons : Nullable;

import laniakea.db;
import laniakea.db.schema.core;
import laniakea.db.schema.synchrotron;
import laniakea.repository;
import laniakea.repository.dak;
import laniakea.db.schema.archive;
import laniakea.utils : compareVersions, getDebianRev, currentDateTime;
import laniakea.localconfig;
import laniakea.logging;

/**
 * Thrown on a package sync error.
 */
class PackageSyncError: Error
{
    @safe pure nothrow
    this (string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super (msg, file, line, next);
    }
}

/**
 * Execute package synchronization in Synchrotron
 */
final class SyncEngine
{

private:
    Database db;
    SessionFactory sFactory;

    Dak dak;
    bool m_importsTrusted;

    Repository sourceRepo;
    Repository targetRepo;

    SyncSourceSuite sourceSuite;
    string targetSuiteName;

    SynchrotronConfig syncConfig;
    BaseConfig baseConfig;

    immutable string distroTag;

public:

    this ()
    {
        dak = new Dak;

        db = Database.get;
        sFactory = db.newSessionFactory! (SyncBlacklistEntry,
                                          SynchrotronIssue);
        auto session = sFactory.openSession ();
        scope (exit) session.close ();

        auto conf = LocalConfig.get;

        baseConfig = db.getBaseConfig;
        syncConfig = db.getSynchrotronConfig;

        // the repository of the distribution we import stuff into
        targetRepo = new Repository (conf.archive.rootPath,
                                     baseConfig.projectName);
        targetRepo.setTrusted (true);

        targetSuiteName = session.getSuite (baseConfig.archive.incomingSuite).name;
        distroTag = baseConfig.archive.distroTag;

        // the repository of the distribution we use to sync stuff from
        sourceRepo = new Repository (syncConfig.source.repoUrl,
                                     syncConfig.sourceName,
                                     conf.synchrotron.sourceKeyrings);
        m_importsTrusted = true; // we trust everything by default

        setSourceSuite (syncConfig.source.defaultSuite);
    }

    private auto getPackageBlacklistSet ()
    {
        auto session = sFactory.openSession ();
        scope (exit) session.close ();

        auto q = session.createQuery ("FROM SyncBlacklistEntry");
        SyncBlacklistEntry[] list = q.list!SyncBlacklistEntry;

        bool[string] blacklistSet;
        foreach (ref entry; list)
            blacklistSet[entry.pkgname] = true;

        return blacklistSet;
    }

    @property
    bool importsTrusted ()
    {
        return m_importsTrusted;
    }

    @property
    void importsTrusted (bool v)
    {
        m_importsTrusted = v;
    }

    void setSourceSuite (string suiteName)
    {
        auto ret = false;
        foreach (ref suite; syncConfig.source.suites) {
            if (suite.name == suiteName) {
                sourceSuite = suite;
                ret = true;
                break;
            }
        }

        if (!ret)
            throw new Exception ("The source suite name '%s' is unknown.".format (suiteName));
    }

    private void checkSyncReady ()
    {
        if (!syncConfig.syncEnabled)
            throw new PackageSyncError ("Synchronization is disabled.");
    }

    /**
     * Get an associative array of the newest packages present in a repository.
     */
    private T[string] getRepoPackageMap(T, R) (R repo, string suiteName, string component, string arch = null, bool withInstaller = true)
        if (is(T == SourcePackage) || is(T == BinaryPackage))
    {
        T[] pkgList;
        static if (is(T == SourcePackage)) {
            pkgList = repo.getSourcePackages (suiteName, component);
        } else static if (is(T == BinaryPackage)) {
            pkgList = repo.getBinaryPackages (suiteName, component, arch);
            pkgList ~= repo.getBinaryPackages (suiteName, component, "all"); // always append arch:all packages
        } else {
            assert (0);
        }

        auto pkgMap = getNewestPackagesAA (pkgList);
        static if (is(T == BinaryPackage)) {
            if (withInstaller) {
                // and d-i packages to the mix
                auto ipkgList = repo.getInstallerPackages (suiteName, component, arch);
                ipkgList ~= repo.getInstallerPackages (suiteName, component, "all"); // always append arch:all packages
                auto ipkgMap = getNewestPackagesAA (ipkgList);

                foreach (ref name, ref pkg; ipkgMap)
                    pkgMap[name] = pkg;
            }
        }

        pkgMap.rehash; // makes lookups slightly faster later
        return pkgMap;
    }

    /**
     * Get an associative array of the newest packages present in the repository we pull packages from.
     * Convenience function for getRepoPackageMap.
     */
    private T[string] getSourceRepoPackageMap(T) (string component, string arch = null, bool withInstaller = true)
        if (is(T == SourcePackage) || is(T == BinaryPackage))
    {
        return getRepoPackageMap!T (sourceRepo,
                                    sourceSuite.name,
                                    component,
                                    arch,
                                    withInstaller);
    }

    /**
     * Get an associative array of the newest packages present in the repository we import the new packages into.
     * Convenience function for getRepoPackageMap.
     */
    private T[string] getTargetRepoPackageMap(T) (string component, string arch = null, bool withInstaller = true)
        if (is(T == SourcePackage) || is(T == BinaryPackage))
    {
        return getRepoPackageMap!T (targetRepo,
                                    targetSuiteName,
                                    component,
                                    arch,
                                    withInstaller);
    }

    /**
     * Import an arbitrary amount of packages via the archive management software.
     */
    private bool importPackageFiles (const string suite, const string component, const string[] fnames)
    {
        return dak.importPackageFiles (suite, component, fnames, importsTrusted, true);
    }

    /**
     * Import a source package from the source repository into the
     * target repo.
     */
    private bool importSourcePackage (SourcePackage spkg, string component)
    {
        string dscfile;
        foreach (file; spkg.files) {
            // the source repository might be on a remote location, so we need to
            // request each file to be there.
            // (dak will fetch the files referenced in the .dsc file from the same directory)
            if (file.fname.endsWith (".dsc"))
                dscfile = sourceRepo.getFile (file);
            sourceRepo.getFile (file);
        }

        if (dscfile.empty) {
            logError ("Critical consistency error: Source package %s in repository %s has no .dsc file.", spkg.name, sourceRepo.baseDir);
            return false;
        }

        return importPackageFiles (targetSuiteName, component, [dscfile]);
    }

    /**
     * Import binary packages for the given set of source packages into the archive.
     */
    private bool importBinariesForSources (SourcePackage[] spkgs, string component, bool ignoreTargetChanges = false)
    {
        import std.array : array;
        import std.algorithm : map;

        if (!syncConfig.syncBinaries) {
            logDebug ("Skipping binary syncs.");
            return true;
        }

        auto session = sFactory.openSession ();
        scope (exit) session.close ();

        // list of valid architectrures supported by the target
        auto incomingSuite = session.getSuite (baseConfig.archive.incomingSuite);
        immutable targetArchs = array (incomingSuite.architectures[].map!(a => a.name)).idup;

        // cache of binary-package mappings for the source
        BinaryPackage[string][string] binPkgArchMap;
        foreach (ref arch; targetArchs) {
            binPkgArchMap[arch] = getSourceRepoPackageMap!BinaryPackage (component, arch);
        }

        // cache of binary-package mappings from the target repository
        BinaryPackage[string][string] destBinPkgArchMap;
        foreach (ref arch; targetArchs) {
            destBinPkgArchMap[arch] = getTargetRepoPackageMap!BinaryPackage (component, arch);
        }

        foreach (ref spkg; spkgs) {
            foreach (ref arch; targetArchs) {
                if (arch !in binPkgArchMap)
                    continue;
                auto binPkgMap = binPkgArchMap[arch];
                auto destBinPkgMap = destBinPkgArchMap[arch];

                auto existingPackages = false;
                auto binFiles = appender!(string[]);
                foreach (ref binI; parallel (spkg.binaries)) {
                    if (binI.name !in binPkgMap) {
                        if (binI.name in destBinPkgMap)
                            existingPackages = true; // package only exists in target
                        continue;
                    }
                    auto binPkg = binPkgMap[binI.name];

                    if (binPkg.sourceName != spkg.name) {
                        logWarning ("Tried to sync binary package '%s' for source package '%s', but binary does not claim to be build by this source.",
                                    binPkg.name, spkg.name);
                        continue;
                    }

                    if (binI.ver != binPkg.sourceVersion) {
                        logDebug ("Not syncing binary package '%s': Version number '%s' does not match source package version '%s'.",
                                  binPkg.name, binI.ver, binPkg.sourceVersion);
                        continue;
                    }

                    auto ebinPkgP = binPkg.name in destBinPkgMap;
                    if (ebinPkgP !is null) {
                        import std.regex : ctRegex, matchAll;

                        auto ebinPkg = *ebinPkgP;
                        if (compareVersions (ebinPkg.ver, binPkg.ver) >= 0) {
                            logDebug ("Not syncing binary package '%s/%s': Existing binary package with bigger/equal version '%s' found.",
                                        binPkg.name, binPkg.ver, ebinPkg.ver);
                            existingPackages = true;
                            continue;
                        }

                        // Filter out manual rebuild uploads matching the pattern XbY.
                        // sometimes rebuild uploads of not-modified packages happen, and if the source
                        // distro did a binNMU, we don't want to sync that, even if it's bigger
                        // This rebuild-upload check must only happen if we haven't just updated the source package
                        // (in that case the source package version will be bigger than the existing binary package version)
                        if (compareVersions (spkg.ver, ebinPkg.ver) <= 0) {
                            auto rbRE = ctRegex!(`([0-9]+)b([0-9]+)`);
                            if (!ebinPkg.ver.matchAll (rbRE).empty) {
                                logDebug ("Not syncing binary package '%s/%s': Existing binary package with rebuild upload '%s' found.",
                                           binPkg.name, binPkg.ver, ebinPkg.ver);
                                existingPackages = true;
                                continue;
                            }
                        }

                        if ((!ignoreTargetChanges) && (ebinPkg.ver.getDebianRev.canFind (distroTag))) {
                            // safety measure, we should never get here as packages with modifications were
                            // filtered out previously.
                            logDebug ("Can not sync binary package %s/%s: Target has modifications.", binI.name, binI.ver);
                            continue;
                        }
                    }

                    auto fname = sourceRepo.getFile (binPkg.file);
                    synchronized (this)
                        binFiles ~= fname;
                }

                // now import the binary packages, if there is anything to import
                if (binFiles.data.length == 0) {
                    if (!existingPackages)
                        logWarning ("No binary packages synced for source %s/%s", spkg.name, spkg.ver);
                } else {
                    auto ret = importPackageFiles (targetSuiteName, component, binFiles.data);
                    if (!ret)
                        return false;
                }
            }
        }

        return true;
    }

    bool syncPackages (const string component, const string[] pkgnames, bool force = false)
    in { assert (pkgnames.length > 0); }
    body
    {
        checkSyncReady ();

        auto destPkgMap = getTargetRepoPackageMap!SourcePackage (component);
        auto srcPkgMap = getSourceRepoPackageMap!SourcePackage (component);

        auto syncBlacklist = getPackageBlacklistSet ();

        auto syncedSrcPkgs = appender!(SourcePackage[]);
        foreach (ref pkgname; pkgnames) {
            auto spkgP = pkgname in srcPkgMap;
            auto dpkgP = pkgname in destPkgMap;

            if (spkgP is null) {
                logInfo ("Can not sync %s: Does not exist in source.", pkgname);
                continue;
            }
            if (pkgname in syncBlacklist) {
                logInfo ("Can not sync %s: The package is blacklisted.", pkgname);
                continue;
            }

            auto spkg = *spkgP;
            if (dpkgP !is null) {
                auto dpkg = *dpkgP;

                if (compareVersions (dpkg.ver, spkg.ver) >= 0) {
                    if (force) {
                        logWarning ("%s: Target version '%s' is newer/equal than source version '%s'.",
                                    pkgname, dpkg.ver, spkg.ver);
                    } else {
                        logInfo ("Can not sync %s: Target version '%s' is newer/equal than source version '%s'.",
                             pkgname, dpkg.ver, spkg.ver);
                        continue;
                    }
                }

                if (!force) {
                    if (dpkg.ver.getDebianRev.canFind (distroTag)) {
                        logError ("No syncing %s/%s: Destination has modifications (found %s).",
                                  spkg.name, spkg.ver, dpkg.ver);
                        continue;
                    }
                }
            }

            // sync source package
            // the source package must always be known to dak first
            auto ret = importSourcePackage (spkg, component);
            if (!ret)
                return false;
            syncedSrcPkgs ~= spkg;
        }

        auto ret = importBinariesForSources (syncedSrcPkgs.data, component, force);

        // TODO: Analyze the input, fetch the packages from the source distribution and
        // import them into the target in their correct order.
        // Then apply the correct, synced override from the source distro.

        return ret;
    }

    private auto newSyncIssue (SyncSourceSuite sourceSuite, ArchiveSuite targetSuite)
    {
        import std.uuid : randomUUID;
        auto issue = new SynchrotronIssue;

        issue.uuid = randomUUID ();
        issue.date = currentDateTime ();

        issue.sourceSuite = sourceSuite.name;
        issue.targetSuite = targetSuite.name;

        return issue;
    }

    /**
     * Synchronize all packages that are newer
     */
    bool autosync ()
    {
        checkSyncReady ();

        auto conn = db.getConnection ();
        scope (exit) db.dropConnection (conn);
        auto session = sFactory.openSession ();
        scope (exit) session.close ();

        auto incomingSuite = session.getSuite (baseConfig.archive.incomingSuite);
        auto targetSuite   = session.getSuite (targetSuiteName);
        auto activeSrcPkgs = appender!(SourcePackage[]); // source packages which should have their binary packages updated

        auto syncBlacklist = getPackageBlacklistSet ();

        // FIXME: we do the quick and dirty update here, removing everything and adding it back.
        // Maybe we need to be smarter about this in future.
        conn.removeSynchrotronIssuesForSuites (sourceSuite.name, incomingSuite.name);

        foreach (ref component; incomingSuite.components) {
            auto destPkgMap = getTargetRepoPackageMap!SourcePackage (component.name);

            // The source package lists contains many different versions, some source package
            // versions are explicitly kept for GPL-compatibility.
            // Sometimes a binary package migrates into another suite, dragging a newer source-package
            // that it was built against with itslf into the target suite.
            // These packages then have a source with a high version number, but might not have any
            // binaries due to them migrating later.
            // We need to care for that case when doing binary syncs (TODO: and maybe safeguard against it
            // when doing source-only syncs too?), That's why we don't filter out the newest packages in
            // binary-sync-mode.
            SourcePackage[] srcPkgRange;
            if (syncConfig.syncBinaries) {
                srcPkgRange = sourceRepo.getSourcePackages (sourceSuite.name, component.name);
            } else {
                auto srcPkgMap = getSourceRepoPackageMap!SourcePackage (component.name);
                srcPkgRange = srcPkgMap.values;
            }

            foreach (ref spkg; srcPkgRange) {
                // ignore blacklisted packages in automatic sync
                if (spkg.name in syncBlacklist)
                    continue;

                auto dpkgP = spkg.name in destPkgMap;
                if (dpkgP !is null) {
                    auto dpkg = *dpkgP;

                    if (compareVersions (dpkg.ver, spkg.ver) >= 0) {
                        logDebug ("Skipped sync of %s: Target version '%s' is equal/newer than source version '%s'.",
                                  spkg.name, dpkg.ver, spkg.ver);
                        continue;
                    }

                    // check if we have a modified target package,
                    // indicated via its Debian revision, e.g. "1.0-0tanglu1"
                    if (dpkg.ver.getDebianRev.canFind (distroTag)) {
                        logInfo ("No syncing %s/%s: Destination has modifications (found %s).", spkg.name, spkg.ver, dpkg.ver);

                        // add information that this package needs to be merged to the issue list
                        auto issue = newSyncIssue (sourceSuite, targetSuite);
                        issue.kind = SynchrotronIssueKind.MERGE_REQUIRED;
                        issue.packageName = spkg.name;
                        issue.targetVersion = dpkg.ver;
                        issue.sourceVersion = spkg.ver;

                        session.save (issue);
                        continue;
                    }
                }

                // sync source package
                // the source package must always be known to dak first
                auto ret = importSourcePackage (spkg, component.name);
                if (!ret)
                    return false;

                // a new source package is always active and needs it's binary packages synced, in
                // case we do binary syncs.
                activeSrcPkgs ~= spkg;
            }

            // all packages in the target distribution are considered active, as long as they don't
            // have modifications.
            // we explicitly use the destPkgMap here, because it always contains only the newest
            // package versions.
            foreach (ref spkg; destPkgMap.byValue) {
                if (!spkg.ver.getDebianRev.canFind (distroTag))
                    activeSrcPkgs ~= spkg;
            }

            // import binaries as well. We test for binary updates for all available active source packages,
            // as binNMUs might have happened in the source distribution.
            // (an active package in this context is any source package which doesn't have modifications in the target distribution)
            auto ret = importBinariesForSources (activeSrcPkgs.data, component.name);
            if (!ret)
                return false;
        }

        // test for cruft packages
        SourcePackage[string] targetPkgIndex;
        foreach (ref component; incomingSuite.components) {
            auto destPkgMap = getTargetRepoPackageMap!SourcePackage (component.name);
            foreach (ref pkgname, ref pkg; destPkgMap)
                targetPkgIndex[pkgname] = pkg;
        }

        // check which packages are present in the target, but not in the source suite
        foreach (ref component; incomingSuite.components) {
            auto srcPkgMap = getSourceRepoPackageMap!SourcePackage (component.name);
            foreach (ref pkgname; srcPkgMap.byKey)
                targetPkgIndex.remove (pkgname);
        }

        // remove cruft packages
        foreach (ref pkgname, ref dpkg; targetPkgIndex) {
            // native packages are never removed
            if (dpkg.ver.getDebianRev (false).empty)
                continue;

            // check if the package is intoduced as new in the distro, in which case we won't remove it
            if (dpkg.ver.getDebianRev.startsWith ("0" ~ distroTag))
                continue;

            // if this package was modified in the target distro, we will also not remove it, but flag it as "potential cruft" for
            // someone to look at.
            if (dpkg.ver.getDebianRev.canFind (distroTag)) {
                auto issue = newSyncIssue (sourceSuite, targetSuite);
                issue.kind = SynchrotronIssueKind.MAYBE_CRUFT;
                issue.packageName = dpkg.name;
                issue.targetVersion = dpkg.ver;
                issue.sourceVersion = null;

                session.save (issue);
                continue;
            }

            // check if we can remove this package without breaking stuff
            if (dak.packageIsRemovable (dpkg.name, targetSuite.name)) {
                // try to remove the package
                try {
                    dak.removePackage (dpkg.name, targetSuite.name);
                } catch (Exception e) {
                    auto issue = newSyncIssue (sourceSuite, targetSuite);
                    issue.kind = SynchrotronIssueKind.REMOVAL_FAILED;
                    issue.packageName = dpkg.name;
                    issue.targetVersion = dpkg.ver;
                    issue.sourceVersion = null;
                    issue.details = "%s".format (e);

                    session.save (issue);
                }
            } else {
                // looks like we can not remove this
                auto issue = newSyncIssue (sourceSuite, targetSuite);
                issue.kind = SynchrotronIssueKind.REMOVAL_FAILED;
                issue.packageName = dpkg.name;
                issue.targetVersion = dpkg.ver;
                issue.sourceVersion = null;
                issue.details = "This package can not be removed without breaking other packages. It needs manual removal.";

                session.save (issue);
            }
        }

        return true;
    }

}
