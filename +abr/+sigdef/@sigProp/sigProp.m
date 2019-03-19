classdef sigProp
% obj = sigProp(value,description,unit,scalingFactor,alternate,type,func)
% 
% Daniel Stolzberg, PhD (c) 2019

    properties
        Value
        
        Alias         (1,:) char
        Description   (1,:) char
        Unit          (1,:) char
        ScalingFactor (1,1) double {mustBeFinite,mustBeNonempty} = 1;
        Function      (1,:) char = '';
        FunctionParams(1,:) cell
        Type          (1,:) char {mustBeMember(Type,{'Numeric','String','File'})} = 'Numeric';
        Alternate     (1,1) logical {mustBeNonempty} = false;
        Active        (1,1) logical {mustBeNonempty} = true;
        Validation    (1,:) char
        
    end
    
    properties (SetAccess = private, GetAccess = public, Dependent)
        DescriptionWithUnit char
        realValue % Value * ScalingFactor
        unitValueString char
        AliasWithUnit (1,:) char
    end
    
    properties (SetAccess = private, GetAccess = public, Dependent, Transient)
        Evaluated % returns eval(obj.Value)
    end
    
    
    methods
        
        % Constructor
        function obj = sigProp(value,description,unit,scalingFactor,alternate,type,func)
            if nargin >= 2 && ~isempty(description),   obj.Description = description;     end
            if nargin >= 3 && ~isempty(unit),          obj.Unit = unit;                   end
            if nargin >= 4 && ~isempty(scalingFactor), obj.ScalingFactor = scalingFactor; end
            if nargin >= 5 && ~isempty(alternate),     obj.Alternate = alternate;         end
            if nargin >= 6 && ~isempty(type),          obj.Type = type;                   end
            if nargin == 7 && ~isempty(func),          obj.Function = func;               end
            
            % this needs to come last so other modifications can be applied
            if nargin >= 1,                            obj.Value = value;                 end
        end
        
        function obj = set.Value(obj,v)
            if isnumeric(v) && ~isempty(obj.Validation) %#ok<MCSUP>
                eval(sprintf(obj.Validation,repmat(v,1,sum(obj.Validation=='%')))); %#ok<MCSUP>
            end
            obj.Value = v;
        end
        
        function v = get.Value(obj)
            if isnumeric(obj.Value)
                v = obj.Value;
            else
                v = obj.Value;
            end
        end
        
        function v = get.realValue(obj)
            v = obj.Evaluated.*obj.ScalingFactor;
%             if isnumeric(obj.Value)
%                 v = obj.Value*obj.ScalingFactor;
%             else
%                 v = obj.Value;
%             end
        end
        
        function s = get.unitValueString(obj)
            if isnumeric(obj.Value)
                s = sprintf('%.2f %s',obj.Value,obj.Unit);
            else
                s = obj.Value;
            end
        end
        
        function s = get.DescriptionWithUnit(obj)
            if isempty(obj.Unit)
                s = obj.Description;
            else
                s = sprintf('%s [%s]',obj.Description,obj.Unit);
            end
        end
        
        function v = get.Evaluated(obj)
            v = obj.Value;
            if ~isempty(obj.Function) || isnumeric(v), return; end
            
            if v(1) ~= '[', v = ['[' v ']']; end
            
            try
                v = eval(v);
            catch me
                rethrow(me)
            end
        end
        
%         function s = get.Alias(obj)
%             if isempty(obj.Alias)
%                 s = obj.Description;
%             else
%                 s = obj.Alias;
%             end
%         end
       
        function s = get.AliasWithUnit(obj)
            if isempty(obj.Unit)
                s = '';
            else
                s = [obj.Alias ' [' obj.Unit ']'];
            end
        end
        
        function s = get.Unit(obj)
            if isempty(obj.Unit)
                s = '';
            else
                s = obj.Unit;
            end
        end
    end
    
end