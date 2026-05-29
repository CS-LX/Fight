local _PACKAGE = "lib/behaviourtree"
local class = require(_PACKAGE..'/middleclass')
local Decorator  = require(_PACKAGE..'/node_types/decorator')
local InvertDecorator = class('InvertDecorator', Decorator)

function InvertDecorator:success()
  self.control:fail()
end

function InvertDecorator:fail()
  self.control:success()
end

return InvertDecorator
