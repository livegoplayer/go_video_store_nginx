ngx.header.content_type = "text/html; charset=utf-8";

local request_uri = ngx.var.request_uri;
local request_uri_without_args = ngx.re.sub(request_uri, "\\?.*", "");

local function mylog(msg)
    
    local cmt_time = '//'..os.date("%m-%d_%H:%M:%S", os.time());
    local file = io.open("/apps/logs/supervisor_openresty_stdout.log","a+");
    file:write(msg..cmt_time..'\n');
    file:flush();
    file:close();
end

local function wait()
   ngx.sleep(math.random(2))
end

local function limit_single_ip() 

  -- 针对单个ip单服务器防刷限流  
  --  1. 引用openresty的流量限制模块
  local limit_req = require "resty.limit.req"

  --  2. 传入共享内存变量，获取rate为30，burst为10限制的流量限制object    
  --  漏桶算法限流
  --  场景：限制 ip 每分钟只能调用 120 次 /hello 接口（平滑处理请求，即每秒放过2个请求），超过部分进入桶中等待，（桶容量为60），如果桶也满了，则进行限流
  local lim, err = limit_req.new("limit_counter", 10, 60)
  if not lim then
      mylog("启动resty.limit失败"..err)
      return ngx.exit(500)
  end

  --  3. 在每次请求时，获取请求中的二进制客户端ip地址作为流量限制的key
  local key = ngx.var.binary_remote_addr

  -- 对key进行流量限制，参数中的true代表要存储每次的计数和毫秒级时间戳
  local delay, err = lim:incoming(key, true)
  if not delay then
      if err == "rejected" then

        mylog("单IP限流成功: "..err)
        return ngx.exit(503)
      end
      mylog("单IP限流失败: "..err)

      return ngx.exit(502)
  end

  if delay >= 0.001 then
    mylog("单IP限流延迟: "..delay)
      ngx.sleep(delay)
  end
end



-- 存在网络请求延迟
local function limit_global_access_by_redis()

  -- 限流策略
  local function close_redis(red)
      if not red then
          return
      end
      --释放连接(连接池实现)
      local pool_max_idle_time = 10000 --毫秒
      local pool_size = 1000 --连接池大小
      local ok, err = red:set_keepalive(pool_max_idle_time, pool_size)
   
      if not ok then
          mylog("set redis keepalive error in php: " .. err)
      end
  end
  
   
  local redis = require "resty.redis"
  local red = redis:new()
  red:set_timeout(500)
  local ip = redis_host; 
  local port = redis_port
  local ok, err = red:connect(ip,port)

  if not ok then
      mylog("php start redis error: " .. err)
      return false
  end
  --设置连接密码 
  if not redis_auth=="" then
      red:auth(redis_auth)
  end
  red:select(redis_db)
   
   -- 获取当前请求的uri 由于ci中间调度都是经由/index.php，此处得到的是固定值
   -- 不过本处正是想做全局的限流策略，固定值则为全局当前请求值
  local uri = ngx.var.uri -- 变量则为 ngx.var.request_uri;
  local uriKey = "req:uri:"..uri
  res, err = red:eval("local res, err = redis.call('incr',KEYS[1]) if res == 1 then local resexpire, err = redis.call('expire',KEYS[1],KEYS[2]) end return (res)",2,uriKey,1)
  if not res then
      return close_redis(red)
  end

  if res > 3000 then
    mylog("超过3000，直接限制访问: "..res)
    close_redis(red)

    return ngx.exit(504)
  end

  -- 全局限流数
  while (res > 2000)
  do 
     local twait, err = ngx.thread.spawn(wait)
     local ok, threadres = ngx.thread.wait(twait)
     if not ok then
        mylog("全局限流失败: "..err)
        break;
     end
     mylog("全局限流成功: 当前请求"..res)
     res, err = red:eval("local res, err = redis.call('incr',KEYS[1]) if res == 1 then local resexpire, err = redis.call('expire',KEYS[1],KEYS[2]) end return (res)",2,uriKey,1)
  end
  close_redis(red)

end

-- 本机限流数，不依赖网络
local function limit_local_access()

  local locks = require "resty.lock"
  local local_lock = ngx.shared.local_lock
  local lock_th, lock_err = locks:new("local_lock")
  if not lock_th then
       mylog("锁初始化失败"..lock_err)
  end
  local elapsed, err = lock_th:lock("local_access_lock") --互斥锁
  local limit_counter = ngx.shared.limit_counter --计数器

  local key = "time:" ..os.time()
  local max_limit = local_max_limit --极限值，超出则抛弃
  local common_limit = local_common_limit --普通限流，超出则等待
  local current, res = limit_counter:incr(key, 1)
  if current == nil then
    limit_counter:set(key, 1, 1) --第一次需要设置过期时间，设置key的值为1，过期时间为1秒
    current = 1
  end


    -- 循环限流，超过瓶颈则等待
    mylog(current)
    mylog(common_limit)
    while (current > common_limit)
    do 
      -- 超过能最大上限，直接抛弃
      if current > max_limit then
        mylog("本机单秒请求数超过限制，被限制访问: "..current)
       
        lock_th:unlock()
        --return ngx.exit(504)
        ngx.say('{"error_code": 1,"msg": "当前访问用户过多，请稍后重试","data": null}');
        ngx.exit(200);
        return
      end

      local twait, err = ngx.thread.spawn(wait)
      local ok, threadres = ngx.thread.wait(twait)
      if not ok then
        mylog("本机限流失败: "..current)
        break;
      end
      mylog("本机限流成功: 当前请求"..current)

      key = "time:" ..os.time()
      current, res = limit_counter:incr(key, 1)

      if current == nil then
        limit_counter:set(key, 1, 1) --第一次需要设置过期时间，设置key的值为1，过期时间为1秒
        current = 1
      end
    end

    lock_th:unlock()
    return false
end

local function limit_url_check(key,s,m)
    local localkey=key;
    local url_limit_share=ngx.shared.url_limit
    local key_m_limit=localkey..os.date("%Y-%m-%d %H:%M", ngx.time())
    local key_s_limit=localkey..os.date("%Y-%m-%d %H:%M:%S", ngx.time())

    local req_key_s,_=url_limit_share:get(key_s_limit);
    local req_key_m,_=url_limit_share:get(key_m_limit);

    -- second count
    if req_key_s then
      url_limit_share:incr(key_s_limit,1)
      if req_key_s > s then
        --mylog('s_time_over:'..request_uri)
        return true
      end
    else
      url_limit_share:set(key_s_limit,1,60)
    end

    -- minute count
    if req_key_m then
      url_limit_share:incr(key_m_limit,1)
      if req_key_m > m then
        --mylog('m_time_over:'..request_uri)
        return true
      end
    else
      url_limit_share:set(key_m_limit,1,60)
    end
    return false
end


-- if ngx.re.match(request_uri_without_args,"/conference/activity_mobile/win(.*)") then

--     if limit_url_check("hb_limit",300,1000) then
--       mylog(request_uri..cmt_time);
--       ngx.say('{"error": 1,"msg": "未中奖","data": ""}');
--       ngx.exit(200);
--       return
--     end
-- end

-- 单IP防刷限制，由于需要做压力测试，可能不能时长开启，后续想动态更改办法，比如读文件判断是否开启
-- limit_single_ip();

-- 全局限流
limit_local_access();

ngx.exec("@client")


