classdef Subject
% obj = Subject(id,alias,dobvec,scientist,note)
%
% Daniel Stolzberg, PhD (c) 2019

    
    properties (Access = public)
        ID          (1,:) char
        Alias       (1,:) char
        Note        (1,:) char
        Scientist   (1,:) char
        DOB         (1,:) char
        
        dataFile    (1,:) char
    end
    
    
    properties (GetAccess = public, SetAccess = private)
        lastUpdated (1,1) datetime
    end
    
    methods
        
        function obj = Subject(id,alias,dob,scientist,note)
            if nargin >= 1 && ~isempty(id),         obj.ID = id;                end
            if nargin >= 2 && ~isempty(alias),      obj.Alias = alias;          end
            if nargin >= 3 && ~isempty(dob),        obj.DOB = dob;              end
            if nargin >= 4 && ~isempty(scientist),  obj.Scientist = scientist;  end
            if nargin == 5 && ~isempty(note),       obj.Note = note;            end
        end
        
        function obj = set.ID(obj,id)
            obj.ID = id;
            obj = obj.updated;
        end
        
        function obj = set.Alias(obj,alias)
            obj.Alias = alias;
            obj = obj.updated;
        end
        
        function obj = set.DOB(obj,dob)
            obj.DOB = dob;
            obj = obj.updated;
        end
        
        function obj = set.Scientist(obj,scientist)
            obj.Scientist = scientist;
            obj = obj.updated;
        end
        
        function obj = set.Note(obj,note)
            obj.Note = note;
            obj = obj.updated;
        end
        
        
    end
    
    methods (Access = private)
        function obj = updated(obj)
            obj.lastUpdated = datetime;
        end
    end
end