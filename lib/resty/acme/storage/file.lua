local _M = {}
local mt = {__index = _M}

function _M.new(conf)
  local dir = conf and conf.dir
  dir = dir or os.getenv("TMPDIR") or '/tmp'

  local self =
    setmetatable(
    {
      dir = dir
    },
    mt
  )
  return self
end

local function regulate_filename(dir, s)
  -- TODO: not windows friendly
  return dir .. "/" .. ngx.encode_base64(s)
end

function _M:set(k, v)
  local f = regulate_filename(self.dir, k)
  local file, err = io.open(f, "wb")
  if err then
    return err
  end
  local _, err = file:write(v)
  if err then
    return err
  end
  file:close()
end

function _M:delete(k)
  local f = regulate_filename(self.dir, k)
  local err = os.remove(f)
  if err then
    return err
  end
end

function _M:get(k)
  local f = regulate_filename(self.dir, k)
  local file, err = io.open(f, "rb")
  if err then
    -- TODO: return nil, nil if not found
    return nil, err
  end
  local output, err = file:read("*a")
  if err then
    return nil, err
  end
  file:close()
  return output, nil
end

function _M:list(prefix)
  error("nyi")
end

return _M
