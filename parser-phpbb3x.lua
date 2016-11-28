-- phpBB 3.x Lua parser for Owl
-- Copyright 2013-2016 Adalid Claure
-- http://www.owlclient.com

--- ######################## NOTE!!! ########################
--- ######## This parser is still under development! ########
--- #########################################################

parserName = "phpbb3"
parserPrettyName = "phpBB 3.x"

-- ****** BOARDWARE CONFIGURATION ******
-- These variables are used by Owl to detect which message board
-- softwares are supported by this parser. These variables must 
-- be present in every Owl parser. 
boardware = "phpbb"
boardwaremin = "3.6"
boardwaremax = "3.9.9.9"

-- Global defaults
PAGENUM  = 1
PERPAGE = 50

-- Implementation
Parser = {}
Parser.__index = Parser

Parser.create = function(url)
	local self = {}

	self.rootForumId = "-1"
	self.baseUrl = url
	self.webclient = webclient.new()

	self.name = parserName
	setmetatable(self, Parser)
	return self
end

function Parser:getForumUrl(forumId)
	local url = ""
	
	if (forumId == self.rootForumId) then
		url = string.format("%s/index.php", self.baseUrl)
	else
		url = string.format("%s/viewforum.php?f=%s", self.baseUrl, forumId)
	end

	return url
end

function Parser:getThreadUrl(threadId)
	return string.format("%s/viewtopic.php?t=%s", self.baseUrl, threadId)	
end

function Parser:getPostUrl(postId)
	return string.format("%s/viewtopic.php?p=%s#p%s", self.baseUrl, postId, postId)
end

function Parser:doGetBoardwareInfo()
	local pageSrc, status, isError = self.webclient:get(self.baseUrl, true)
	local doc = sgml.new(pageSrc)
	local tags = doc:getElementsByName("meta", "name", "generator")

	if (#tags > 0) then
		local tag = tags[1]
		local content = tag:attribute("content")
		local version = string.match(content, "([%d%.]+)")
		
		if (version ~= nil) then
			ret = {}
			
			local titleTag = doc:getElementsByName("title", nil, nil)
			if (#titleTag > 0 and #(titleTag[1]:children()) > 0) then
				local title = titleTag[1]:children()[1]:value()
				
				if (title and string.len(title) > 0) then
					title = string.gsub(title, " %- Powered by vBulletin", "", 1)
					if (string.len(title) > 0) then
						ret["name"] = title
					end
				end				
			end
			
			ret["success"] = true
			ret["boardware"] = "vbulletin"
			ret["version"] = version
			
			return ret
		end
	end

	return { ["success"] = false }
end

function Parser:doTestParser(pageSrc)
	return { ["success"] = false }
end