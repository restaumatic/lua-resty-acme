# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua 'no_plan';
use Cwd qw(cwd);

my $pwd = cwd();

our $MainConfig = qq{
    thread_pool create_pkey threads=1;
};

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;$pwd/lib/?/init.lua;$pwd/../lib/?.lua;$pwd/../lib/?/init.lua;;";
    lua_shared_dict acme 16m;
};

run_tests();

__DATA__

=== TEST 1: init should succeed with domain_key_types_for_domain = nil (default)
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("resty.acme.autossl").init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types_for_domain = nil,
            })
            ngx.say("ok")
        }
    }
--- request
    GET /t
--- error_code: 200
--- response_body
ok
--- no_error_log
[error]

=== TEST 2: init should succeed with valid domain_key_types_for_domain function
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("resty.acme.autossl").init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types_for_domain = function(domain)
                    if domain == "modern.example.com" then
                        return { 'ecc' }
                    end
                    return nil
                end,
            })
            ngx.say("ok")
        }
    }
--- request
    GET /t
--- error_code: 200
--- response_body
ok
--- no_error_log
[error]

=== TEST 3: init should fail with domain_key_types_for_domain as string
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("resty.acme.autossl").init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types_for_domain = "not a function",
            })
        }
    }
--- request
    GET /t
--- error_code: 500
--- error_log
domain_key_types_for_domain must be a function, got string

=== TEST 4: init should fail with domain_key_types_for_domain as number
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("resty.acme.autossl").init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types_for_domain = 123,
            })
        }
    }
--- request
    GET /t
--- error_code: 500
--- error_log
domain_key_types_for_domain must be a function, got number

=== TEST 5: init should fail with domain_key_types_for_domain as table
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            require("resty.acme.autossl").init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types_for_domain = {},
            })
        }
    }
--- request
    GET /t
--- error_code: 500
--- error_log
domain_key_types_for_domain must be a function, got table

=== TEST 6: get_domain_key_types returns global types when callback returns nil
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local autossl = require("resty.acme.autossl")
            autossl.init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types = { 'rsa', 'ecc' },
                domain_key_types_for_domain = function(domain)
                    return nil
                end,
            })
            local types = autossl._test_get_domain_key_types("example.com")
            ngx.say(table.concat(types, ","))
        }
    }
--- request
    GET /t
--- error_code: 200
--- response_body
rsa,ecc
--- no_error_log
[error]

=== TEST 7: get_domain_key_types logs error and returns global types for empty table
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local autossl = require("resty.acme.autossl")
            autossl.init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types = { 'rsa', 'ecc' },
                domain_key_types_for_domain = function(domain)
                    return {}
                end,
            })
            local types = autossl._test_get_domain_key_types("example.com")
            ngx.say(table.concat(types, ","))
        }
    }
--- request
    GET /t
--- error_code: 200
--- response_body
rsa,ecc
--- error_log
domain_key_types_for_domain returned empty table for domain example.com

=== TEST 8: get_domain_key_types logs error and returns global types for non-table (string)
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local autossl = require("resty.acme.autossl")
            autossl.init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types = { 'rsa', 'ecc' },
                domain_key_types_for_domain = function(domain)
                    return "not a table"
                end,
            })
            local types = autossl._test_get_domain_key_types("example.com")
            ngx.say(table.concat(types, ","))
        }
    }
--- request
    GET /t
--- error_code: 200
--- response_body
rsa,ecc
--- error_log
domain_key_types_for_domain returned invalid type 'string' for domain example.com

=== TEST 9: get_domain_key_types logs error and returns global types for non-table (number)
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local autossl = require("resty.acme.autossl")
            autossl.init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types = { 'rsa', 'ecc' },
                domain_key_types_for_domain = function(domain)
                    return 123
                end,
            })
            local types = autossl._test_get_domain_key_types("example.com")
            ngx.say(table.concat(types, ","))
        }
    }
--- request
    GET /t
--- error_code: 200
--- response_body
rsa,ecc
--- error_log
domain_key_types_for_domain returned invalid type 'number' for domain example.com

=== TEST 10: get_domain_key_types logs error and returns global types for invalid type
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local autossl = require("resty.acme.autossl")
            autossl.init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types = { 'rsa', 'ecc' },
                domain_key_types_for_domain = function(domain)
                    return { "invalid_type" }
                end,
            })
            local types = autossl._test_get_domain_key_types("example.com")
            ngx.say(table.concat(types, ","))
        }
    }
--- request
    GET /t
--- error_code: 200
--- response_body
rsa,ecc
--- error_log
domain_key_types_for_domain returned invalid type 'invalid_type' for domain example.com

=== TEST 11: get_domain_key_types returns valid subset
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local autossl = require("resty.acme.autossl")
            autossl.init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types = { 'rsa', 'ecc' },
                domain_key_types_for_domain = function(domain)
                    return { 'ecc' }
                end,
            })
            local types = autossl._test_get_domain_key_types("example.com")
            ngx.say(table.concat(types, ","))
        }
    }
--- request
    GET /t
--- error_code: 200
--- response_body
ecc
--- no_error_log
[error]

=== TEST 12: get_domain_key_types respects order of returned types
--- main_config eval: $::MainConfig
--- http_config eval: $::HttpConfig
--- config
    location /t {
        content_by_lua_block {
            local autossl = require("resty.acme.autossl")
            autossl.init({
                tos_accepted = true,
                account_email = "test@example.com",
                domain_whitelist = { "example.com" },
                storage_adapter = "shm",
                storage_config = {
                    shm_name = 'acme',
                },
                domain_key_types = { 'rsa', 'ecc' },
                domain_key_types_for_domain = function(domain)
                    return { 'ecc', 'rsa' }
                end,
            })
            local types = autossl._test_get_domain_key_types("example.com")
            ngx.say(table.concat(types, ","))
        }
    }
--- request
    GET /t
--- error_code: 200
--- response_body
ecc,rsa
--- no_error_log
[error]
