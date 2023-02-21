
--单机限流极限值，超出则抛弃
local_max_limit = 300
--单机限流标准值，超出则等待
local_common_limit = 150 --普通限流，超出则等待

redis_host = os.getenv("LUA_REDIS_HOST")
redis_port = os.getenv("LUA_REDIS_PORT")
redis_auth = os.getenv("LUA_REDIS_AUTH")
redis_db = os.getenv("LUA_REDIS_DB")

