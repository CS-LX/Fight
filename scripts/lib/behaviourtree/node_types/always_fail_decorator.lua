local _PACKAGE = "lib/behaviourtree"
local class = require(_PACKAGE..'/middleclass')
local Decorator  = require(_PACKAGE..'/node_types/decorator')
local AlwaysFailDecorator = class('AlwaysFailDecorator', Decorator)

function AlwaysFailDecorator:success()
  self.control:fail()
end

function AlwaysFailDecorator:fail()
  self.control:fail()
end

return AlwaysFailDecorator

