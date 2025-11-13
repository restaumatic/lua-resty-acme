# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua 'no_plan';
use Cwd qw(cwd);


my $pwd = cwd();

our $MainConfig = qq{
    thread_pool create_pkey threads=1;
};

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;$pwd/lib/?/init.lua;$pwd/../lib/?.lua;$pwd/../lib/?/init.lua;;";
};

our $TestConfig = q{
    location /t {
        content_by_lua_block {
            require("resty.acme.autossl").init({
                tos_accepted = true,
                account_email = "youemail@youdomain.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "redis",
                storage_config = {
                    namespace = ngx.var.uri:sub(4),
                }
            })
        }
    }
};

run_tests();

__DATA__
=== TEST 1: should fail if namespace is prefixed with update_lock:
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config eval: $::TestConfig
--- request
    GET /t/update_lock%3A
--- error_code: 500
--- error_log
namespace can't be prefixed with reserved word: update_lock:

=== TEST 2: should fail if namespace is prefixed with domain:
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config eval: $::TestConfig
--- request
    GET /t/domain%3Aaaa
--- error_code: 500
--- error_log
namespace can't be prefixed with reserved word: domain:

=== TEST 3: should fail if namespace is prefixed with account_key:
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config eval: $::TestConfig
--- request
    GET /t/account_key%3Abbb
--- error_code: 500
--- error_log
namespace can't be prefixed with reserved word: account_key:

=== TEST 4: should fail if namespace is prefixed with failure_lock:
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config eval: $::TestConfig
--- request
    GET /t/failure_lock%3Accc
--- error_code: 500
--- error_log
namespace can't be prefixed with reserved word: failure_lock:

=== TEST 5: should fail if namespace is prefixed with failed_attempts:
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config eval: $::TestConfig
--- request
    GET /t/failed_attempts%3Addd
--- error_code: 500
--- error_log
namespace can't be prefixed with reserved word: failed_attempts:

=== TEST 6: should success if namespace is suffixed with reserved word
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config eval: $::TestConfig
--- request
    GET /t/xxxupdate_lock%3A
--- error_code: 200
--- no_error_log
[error]

=== TEST 7: should success if namespace is infixed with reserved word
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config eval: $::TestConfig
--- request
    GET /t/xxxupdate_lock%3Ayyy
--- error_code: 200
--- no_error_log
[error]

=== TEST 8: should success with other normal namespace
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config eval: $::TestConfig
--- request
    GET /t/normalname
--- error_code: 200
--- no_error_log
[error]
