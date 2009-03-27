--==============================================================================
-- Kernel
--
-- gtimworks@gmail.com, 2009
-- 
-- Kernel API:
-- create
-- kill
-- run
--==============================================================================

local kernel               = nil;
local self                 = nil;
local iCounter             = 1;

local INSTRUCTION_DEFAULT  = 10000;
local INSTRUCTION_TICK     = 100;
local INSTRUCTION_KILL     = -1000;

--------------------------------------------------------------------------------
-- utility functions
--------------------------------------------------------------------------------
----------------------------------------------------------------------------
-- dump
--
-- dump kernel process list
----------------------------------------------------------------------------
local function dump()
    print("====================");
    local pTmp = kernel.self.pHead;
    while nil ~= pTmp do
        print("proc: ",pTmp,
              "pid: ",pTmp.pid(),
              "dead: ",pTmp.isDead());
        pTmp = pTmp.pNext;
    end
    print("====================");
end

----------------------------------------------------------------------------
-- deepCopy
--
-- duplicate an object
----------------------------------------------------------------------------
local function deepCopy(object)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end

--------------------------------------------------------------------------------
-- proc functions
--------------------------------------------------------------------------------
----------------------------------------------------------------------------
-- local sandboxFunction
--
-- sandboxing an untrusted function the call it
----------------------------------------------------------------------------
local function proc_sandboxFunction()
    -- always start pCurrent
    local proc = self.pCurrent;
    if (proc.player.entry)
    then
        proc.player.entry(proc.game);
    end
end

--------------------------------------------------------------------------------
-- proc_create
--
-- create a new proc
--------------------------------------------------------------------------------
local function proc_create(pid,
                           untrustedCode,
                           sandbox,
                           game)
    local player = nil;

    -- load untrustedCode
    local untrustedFunction, message = loadstring(untrustedCode);
    if untrustedFunction
    then 
        setfenv(untrustedFunction,
                kernel.sandbox);
        player = untrustedFunction();
    else
        -- fail to parse untrustedCode, error out
        print(message);
    end

    if (player)
    then
        return {
            pid               = pid,
            player            = player,
            sandbox           = sandbox,
            game              = game,
            
            bDead             = false,
            time              = 0,
            errorMessage      = "",
            coRoot            = coroutine.create(proc_sandboxFunction),
        };
    else
        return nil;
    end
end

----------------------------------------------------------------------------
-- proc_error
--
-- record message to errorMessage
----------------------------------------------------------------------------
local function proc_error(proc,
                          message)
    proc.errorMessage = proc.errorMessage..message;
end

----------------------------------------------------------------------------
-- proc_tick
--
-- reduce process's time
----------------------------------------------------------------------------
local function proc_tick(proc)
    proc.time = proc.time - INSTRUCTION_TICK;
    
    -- mark dead if timeout
    if (proc.time < INSTRUCTION_KILL)
    then
        -- kill the proccess
        error("coroutine timeout, killed",
              2);
    end
end

----------------------------------------------------------------------------
-- proc_isDead
--
-- return true if the process is dead
----------------------------------------------------------------------------
local function proc_isDead(proc)
    return (true == proc.bDead
            or "dead" == coroutine.status(proc.coRoot));
end

----------------------------------------------------------------------------
-- proc_kill
--
-- mark the bDead flag
----------------------------------------------------------------------------
local function proc_kill(proc)
    proc.bDead = true;
end

----------------------------------------------------------------------------
-- coroutine API
----------------------------------------------------------------------------
----------------------------------------------------------------------------
-- co_hook
--
-- the debug hook function 
----------------------------------------------------------------------------
local function co_hook()
    proc_tick(self.pCurrent);
end

----------------------------------------------------------------------------
-- co_setHook
--
-- set debug hook to a process
----------------------------------------------------------------------------
local function co_setHook(co)
    -- set hook to co
    debug.sethook(co,
                  co_hook,
                  "",
                  INSTRUCTION_TICK);
end

----------------------------------------------------------------------------
-- co_resetHook
--
-- reset debug hook to a process
----------------------------------------------------------------------------
local function co_resetHook()
    -- reset hook
    debug.sethook();
end

----------------------------------------------------------------------------
-- kernel API
----------------------------------------------------------------------------

----------------------------------------------------------------------------
-- kernel_create
--
-- create a process, return the pid of the process
----------------------------------------------------------------------------
local function kernel_create(untrustedCode,
                             game)
    local proc = proc_create(iCounter,
                             untrustedCode,
                             kernel.sandbox,
                             game);
    iCounter = iCounter + 1;
    
    -- add process to list
    proc.pNext = self.pHead;
    self.pHead = proc;
    
    return proc.pid;
end

----------------------------------------------------------------------------
-- kernel_kill
--
-- kill a process. just mark the bDead flag.
-- This function returns true if the process is found. returns false
-- otherwise.
----------------------------------------------------------------------------
local function kernel_kill(pid)
    -- search the process
    local bResult = false;
    local pTmp = self.pHead;
    
    while(nil ~= pTmp)
    do
        if (pid == pTmp.pid)
        then
            proc_kill(pTmp);
            bResult = true;
            break;
        end
        pTmp = pTmp.pNext;
    end
    
    return bResult;
end

----------------------------------------------------------------------------
-- kernel_run
--
-- each process has maximum "ticks" number of instructions. If it takes 
-- self.INSTRUCTION_KILL more than that the process will be killed.
-- The default ticks will be self.INSTRUCTION_MAX
-- This functions returns number of active processes.
----------------------------------------------------------------------------
local function kernel_run(ticks)
    local bResumeResult = nil;
    local param = nil;

    if (nil == ticks)
    then
        ticks = INSTRUCTION_DEFAULT;
    end
    
    local procNum = 0;
    self.pCurrent = self.pHead;

    while (nil ~= self.pCurrent)
    do
        if (true ~= proc_isDead(self.pCurrent))
        then
            self.pCurrent.time = ticks;
            local co = self.pCurrent.coRoot;

            -- set hook to coRoot
            co_setHook(co);
            bResumeResult, param = coroutine.resume(co);
            -- reset hook
            co_resetHook();
            
            if (true == bResumeResult)
            then
                procNum = procNum + 1;
            else
                -- dump error message
                proc_error(self.pCurrent,
                           tostring(co).." "..param.."\n");
                print("\n=== Proc "..self.pCurrent.pid.." Error ===");
                print(self.pCurrent.errorMessage.."=========\n");
            end
        end
        self.pCurrent = self.pCurrent.pNext;
    end

    return procNum;
end

----------------------------------------------------------------------------
-- Sandbox
----------------------------------------------------------------------------
----------------------------------------------------------------------------
-- processYield
--
-- yield the execution of the whole process. This include tracking the 
-- coroutine.resume and yield out all running coroutines when required
----------------------------------------------------------------------------
local function processYield()
    coroutine.yield(true);
end

----------------------------------------------------------------------------
-- threadYield
--
-- yield the execution of the current coroutine.
----------------------------------------------------------------------------
local function threadYield(...)
    coroutine.yield(false,
                    ...);
end

----------------------------------------------------------------------------
-- threadResume
--
-- start/resume execution of a coroutine, each resume at least takes
-- INSTRUCTION_TICK instructions
----------------------------------------------------------------------------
local function threadResume(newCo,
                            ...)
    if ("thread" ~= type(newCo))
    then
        error("bad param #1 to 'thread.resume' (thread expected)");
    end

    local oldCo = coroutine.running();

    -- tick oldCo
    proc_tick(self.pCurrent);
    while(true)
    do
        -- set hook
        co_setHook(newCo);
        bResumeResult, processFlag, param = coroutine.resume(newCo,
                                                             ...);
        co_resetHook();

        -- when resume returns, there are 3 possibilities
        -- 1. error. (false == bResumeResult)
        --    escalate error
        -- 2. processYield. (true == procYieldFlag)
        --    just yield out, when yield returns, resume back
        -- 3. child coroutine yield. (otherwise)
        --    tick time
        --    hook oldCo
        --    break out the loop to return the function
        if (false == bResumeResult)
        then
            -- dump error message
            proc_error(self.pCurrent,
                       tostring(newCo).." "..processFlag.."\n");
            
            -- kill oldCo too
            error("child coroutine error, escalate",
                  2);
        else
            if (true == processFlag)
            then
                -- continue yield if it is processYidle
                -- we don't need to pass resume resume since processYield
                -- doesn't take parameters
                processYield();
            else
                -- tick newCo
                proc_tick(self.pCurrent);
                -- set hook to oldCo
                co_setHook(oldCo);
                -- not processYield, return
                break;
            end
        end
    end

    return true, param;
end

--------------------------------------------------------------------------------
-- private initKernel
--------------------------------------------------------------------------------
local function initKernel()
    kernel = {};
    self = {};
    self.pHead = nil;
    self.pCurrent = nil;

    -- kernel API
    kernel.create    = kernel_create;
    kernel.kill      = kernel_kill;
    kernel.run       = kernel_run;

    ----------------------------------------------------------------------------
    -- sandbox
    ----------------------------------------------------------------------------
    local sandbox_thread = {
        create  = coroutine.create,
        wrap    = coroutine.wrap,
        yield   = coroutine.yield,
        running = coroutine.running,
        status  = coroutine.status,
        resume  = threadResume,
    };
    
    local sandbox_process = {
        pid      = 
            function()
                return self.pCurrent.pid;
            end,
        time = 
            function()
                return self.pCurrent.time;
            end,
        yield    = processYield,
        yieldOnTimeout = 
            function()
                if (self.pCurrent.time < 0)
                then
                    return processYield();
                else
                    return false;
                end
            end,
    };
    
    kernel.sandbox =  {
        -- lua default variables
        assert = assert,
        erro   = error,
        ipairs = ipairs,
        next   = next,
        pairs  = pairs,
        select = select,
        tonumber = tonumber,
        tostring = tostring,
        type     = type,
        unpack   = unpack,
        loadstring = loadstring,

        -- deepCopy the lua tables
        math   = deepCopy(math),
        string = deepCopy(string),
        table  = deepCopy(table),

        thread  = sandbox_thread,
        process = sandbox_process,
        
        -- for debugging purpose
        print  = print,
        --debug  = deepCopy(debug),
    };
    setmetatable(kernel.sandbox, {__index = kernel.sandbox});
end

--------------------------------------------------------------------------------
-- Constructor [DP: Silgleton]
--------------------------------------------------------------------------------
function getKernel()
    if (nil == kernel)
    then
        initKernel();
    end
    return kernel;
end


