-- Highlight box for the on-screen keyboard used by ScreenTextEntryVisual.
-- PositionCursor() in ScreenTextEntry.cpp plays "RegularKey" for single-character
-- keys and "SpecialKey" for the wider Space/Backspace/Cancel/Done labels.
return Def.Quad{
	InitCommand=function(self) self:diffuse(color("#44CCFFCC")) end,
	RegularKeyCommand=function(self) self:setsize(28,28) end,
	SpecialKeyCommand=function(self) self:setsize(88,28) end,
};
