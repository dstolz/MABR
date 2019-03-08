classdef Click < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019
    
    methods
        
        % Constructor
        function obj = Click(duration)
            if nargin < 1 || isempty(duration), duration = 0.0005; end
            
            obj.duration = duration;

        end
        
        function update(obj)
            obj.data = ones(1,obj.N);
        end
    end
    
    
    methods (Static)
        function obj = createDisplay(parent)
            % setup custom fields in some parent figure or panel
        end
    end
    
end