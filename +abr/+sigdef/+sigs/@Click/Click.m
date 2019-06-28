classdef Click < abr.sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019
    
    
    properties (Constant)
        type = 'Click';
    end
    
    methods
        
        % Constructor
        function obj = Click(duration)
            obj.ignoreProcessUpdate = true;
            
            if nargin < 1 || isempty(duration), duration = 0.01; end
            
            obj.duration.Value = duration;
            
            % deactivate some default parametes
            obj.windowFcn.Active    = false;
            obj.windowOpts.Active   = false;
            obj.windowRFTime.Active = false;
                        
            obj.SortProperty = 'duration';
            
            obj.informativeParams = {'duration'};
            
            obj.ignoreProcessUpdate = false;
        end
        
        function obj = update(obj)

            A = obj.soundLevel.realValue;
            D = obj.duration.realValue;

            k = 1;

            for a = 1:length(A)
                 % first check if calibration has been done
                 if obj.calibration_is_valid
                    A_V = obj.calibration.estimate_calibrated_voltage(freq(m),A(a));
                else
                    A_V = 1;
                end

                for d = 1:length(D)
                    y = A_V .* ones(1,round(obj.Fs*D(d)));
                    obj.data{k,1} = y;
                    obj.dataParams.soundLevel = A(a);
                    obj.dataParams.duration   = D(d);
                end
            end
            
            % no gating
        end
    end
    
    
end