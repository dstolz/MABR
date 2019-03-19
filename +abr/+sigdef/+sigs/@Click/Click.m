classdef Click < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019
    
    methods
        
        % Constructor
        function obj = Click(duration)
            obj.Type = 'Click';
            
            if nargin < 1 || isempty(duration), duration = 0.01; end
            
            obj.duration.Value = duration;
            
            % deactivate some default parametes
            obj.windowFcn.Active = false;
            obj.windowOpts.Active = false;
            obj.windowRFTime.Active = false;
            
            obj.soundLevel.Value = '0:10:80';
        end
        
        function update(obj)
            obj.data = ones(1,obj.N);
        end
    end
    
    
end