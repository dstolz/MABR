classdef Help < handle
    
    % TO BE CREATED
    
    properties (SetAccess = private)
        ABRGlobal (1,1) abr.ABRGlobal = abr.ABRGlobal;
    end
    
    properties (SetAccess = protected)
        
    end
    
    
    
    methods
        
        % Constructor
        function obj = Help
            
        end
        
        % Destructor
        function delete(obj)
            % close all open messages (??)
        end
        
        
        function alert(obj,msg)
            
        end
                
        
    end
    
end