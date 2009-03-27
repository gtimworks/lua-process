local function f1(game)
    for i=1,20 do
        x = 0;
        for j=0, 300 do
            process.yieldOnTimeout();
            x = x + math.sin(j/i)
        end
        print(process.pid(), i, x);
    end
end

return {
    name    = "player 1",
    version = 0.1,
    author  = "Tim",
    entry   = f1,
}
