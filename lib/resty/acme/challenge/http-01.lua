local base_challenge = require("resty.acme.challenge")

local _M = base_challenge.extend()
local mt = {__index = _M}

function _M.new(storage)
  local self = setmetatable({
    -- TODO: will this ever change?
    uri_prefix = "acme-challenge",
  }, mt)

  self:set_storage(storage)
  return self
end

function _M:serve_challenge()
  local uri = ngx.var.request_uri

  local captures, err =
    ngx.re.match(ngx.var.request_uri, [[\.well-known/]] .. self.uri_prefix .. "/(.+)", "jo")

  if err or not captures[1] then
    ngx.log(ngx.ERR, "error extracting token from request_uri ", err)
    ngx.exit(400)
  end

  local token = captures[1]

  ngx.log(ngx.DEBUG, "token is ", token)

  local value, err = self.storage:get(token)

  if err then
    ngx.log(ngx.ERR, "error getting challenge response from storage ", err)
    ngx.exit(500)
  end

  if not value then
    ngx.log(ngx.ERR, "no corresponding response found for ", token)
    ngx.exit(404)
  end

  ngx.say(value)
end

return _M
