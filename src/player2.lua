function f2_co(game)
    for i=1,20 do
        x = 0;
        for j=0, 100 do
            process.yieldOnTimeout();
            x = x + math.sin(j/i)
        end
        print("f2_co", process.pid(), i, x);
    end   
end

function f2(game)
    print("version: ", game.version);
    -- create thread
    local co = thread.create(f2_co);
    thread.resume(co,
                  game);

    for i=1,20 do
        x = 0;
        for j=0, 30 do
            process.yieldOnTimeout();
            x = x + math.sin(j/i)
        end
        print("f2", process.pid(), i, x);
    end
end

return {
    name    = "player 2",
    version = 0.1,
    author  = "Tim",
    entry   = f2,
}
