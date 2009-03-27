--==============================================================================
-- test kernel and process
--==============================================================================
require "kernel"

local function readFile(filename)
    local file = io.open(filename,
                         "r");
    return file:read("*a");
end

function main()
    -- init kernel
    local kernel = getKernel();
    -- init game
    local game = {};
    game.version = 0.1;

    local code1 = readFile("player1.lua");
    local code2 = readFile("player2.lua");

    local pid1 = kernel.create(code1,
                               game);
    local pid2 = kernel.create(code2,
                               game);
    local pid3 = kernel.create(code1,
                               game);
    local pid4 = kernel.create(code2,
                               game);

    while(true) do
        print("--- kernel run() ---");
        if (0 == kernel.run())
        then
            -- no more active process
            break;
        end
    end
end

--------------------------------------------------------------------------------
-- main entry
--------------------------------------------------------------------------------
main();