-- An observation heuristic, never authority to accept a gameplay command.
local settle = {}

function settle.new(requiredSamples)
    assert(requiredSamples >= 2 and requiredSamples % 1 == 0)
    local observer = { required = requiredSamples }
    function observer:reset()
        self.previous = nil
        self.count = 0
        self.emitted = false
    end
    function observer:sample(idle, canonical)
        if idle ~= true or type(canonical) ~= 'string' then
            self:reset()
            return false
        end
        if canonical ~= self.previous then
            self.previous = canonical
            self.count = 1
            self.emitted = false
        else
            self.count = self.count + 1
        end
        if self.count >= self.required and not self.emitted then
            self.emitted = true
            return true
        end
        return false
    end
    observer:reset()
    return observer
end

return settle
