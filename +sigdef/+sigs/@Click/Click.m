classdef Click < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019
    
    properties (Constant = true)
        A_polarity      = true;
    end
    
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
    
    
end