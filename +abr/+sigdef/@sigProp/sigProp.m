classdef (Hidden) sigProp %< matlab.mixin.SetGet
% obj = sigProp(value,description,unit,scalingFactor,alternate,type,func)
% 
% Daniel Stolzberg, PhD (c) 2019

    properties
        Value % variable size and type
        
        Alias         (1,:) char
        Description   (1,:) char
        Unit          (1,:) char
        ScalingFactor (1,1) double {mustBeFinite,mustBeNonempty} = 1;
        Function      (1,:) char
        FunctionParams(1,:) cell
        Type          (1,:) char {mustBeMember(Type,{'Numeric','String','File'})} = 'Numeric';
        Alternate     (1,1) logical {mustBeNonempty} = false;
        Active        (1,1) logical {mustBeNonempty} = true;
        Validation    (1,:) char
        MaxLength     (1,1) double {mustBePositive} = inf;
        MinValue      (1,1) double = -inf; % in real units
        MaxValue      (1,1) double = inf;  % in real units
        ValueFormat   (1,:) char = '%g';
        Dependency    (1,:) char {mustBeMember(Dependency,{'Nyquist','Duration','None'})} = 'None';
        
        Pairing       (1,:) char % not yet implemented, but should be used in the future to define parameter pairs
    end
    
    properties (SetAccess = private, Dependent)
        DescriptionWithUnit char
        realValue % Value * ScalingFactor
        unitValueString char
        AliasWithUnit (1,:) char
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
                
            oldVal = obj.Value;
            obj.Value = v;
            
            e = obj.Evaluated;
            if length(e) > obj.MaxLength
                obj.Value = oldVal;
                error('abr:sigProp:tooManyValues', ...
                    'Signal Property Value Too Long. Must be less than or equal to %d',obj.MaxLength);
            end
            
            if ~isnumeric(e), return; end
            try
                assert(~any(e * obj.ScalingFactor < obj.MinValue), 'abr:sigProp:belowMinValue', ...
                    ['Values must be greater than or equal to ' obj.ValueFormat obj.Unit], ...
                    obj.MinValue / obj.ScalingFactor);
                
                assert(~any(e * obj.ScalingFactor > obj.MaxValue), 'abr:sigProp:exceedMaxValue', ...
                    ['Values must be less than or equal to ' obj.ValueFormat obj.Unit], ...
                    obj.MaxValue / obj.ScalingFactor);
            catch me
                obj.Value = oldVal;
                rethrow(me);
            end
        end
        
        function v = get.Value(obj)
            if iscellstr(obj.Value)
                v = char(obj.Value);
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
            try
                v = obj.Evaluated;
            catch
                s = obj.Value;
                return
            end
            s = '';
            for i = 1:length(v)
                s = sprintf(['%s' obj.ValueFormat ' %s,'],s,v(i),obj.Unit);
            end
            s(end) = [];
            
        end
        
        function s = get.DescriptionWithUnit(obj)
            if isempty(obj.Unit)
                s = obj.Description;
            else
                s = sprintf('%s [%s]',obj.Description,obj.Unit);
            end
        end
        
        function v = get.Evaluated(obj)
            ov = obj.Value;
            v = ov;
            if ~isempty(obj.Function) || isnumeric(v), return; end
            
            if iscellstr(v), v = char(v); end
            
            if v(1) ~= '[', v = ['[' v ']']; end
            
            try
                v = eval(v);
            catch me
                v = ov;
                %rethrow(me)
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
        
        
        function d = info_text(obj)
            if ischar(obj.Value)
                d = sprintf('%s:\t%s %s',obj.DescriptionWithUnit,obj.Value);
            elseif iscellstr(obj.Value)
                d = sprintf('%s:\t%s %s',obj.Description,char(obj.Value),obj.Unit);
            else
                d = sprintf(['%s:\t' obj.ValueFormat ' %s'],obj.Description,obj.Value,obj.Unit);
            end
        end
        
        % overloaded functions
        function disp(obj)
            fprintf('\t%s\n',obj.info_text)
            
        end
    end
    
    
end