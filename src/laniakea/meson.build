# Meson definition for Laniakea - Shared

laniakea_lib_src = [
    'localconfig.d',
    'compressed.d',
    'debcheck.d',
    'downloadmanager.d',
    'git.d',
    'logging.d',
    'net.d',
    'tagfile.d',
    'repository/dak.d',
    'repository/package.d',
    'repository/dscfile.d',
    'repository/repository.d',
    'utils/consts.d',
    'utils/gpg.d',
    'utils/package.d',
    'utils/utils.d',
    'utils/versioncmp.d',
    'utils/namegen.d',
    'db/package.d',
    'db/database.d',
    'db/maintenance.d',
    'db/utils.d',
    'db/schema/package.d',
    'db/schema/core.d',
    'db/schema/archive.d',
    'db/schema/ariadne.d',
    'db/schema/jobs.d',
    'db/schema/debcheck.d',
    'db/schema/synchrotron.d',
    'db/schema/spears.d',
    'db/schema/planter.d',
    'db/schema/workers.d',
    'db/schema/isotope.d'
]

lk_base_deps = [crypto_dep,
                ssl_dep,
                dcontainers_dep,
                archive_dep,
                curl_dep,
                czmq_dep,
                dyaml_dep,
                ddbc_pg_dep,
                hibernated_pg_dep,
                vibe_core_dep,
                vibe_data_dep
]

laniakea_lib = static_library ('laniakea',
    [laniakea_lib_src],
    include_directories: [src_dir],
    link_with: [lk_cbind_lib],
    dependencies: [lk_base_deps],
    d_args: ['-J' + source_root + '/data/']
)

laniakea_shared_dep = declare_dependency(
    dependencies: [lk_base_deps],
    link_with: [laniakea_lib],
    include_directories: [src_dir],

)

# Test
lk_shared_test_exe = executable ('lk_test_self-core',
    [laniakea_lib_src],
    include_directories: [src_dir],
    link_with: [lk_cbind_lib],
    dependencies: [lk_base_deps],
    d_args: d_unittest_args + ['-J' + source_root + '/data/'],
    link_args: '-main',
)
test('lk_test_self-core', lk_shared_test_exe)
