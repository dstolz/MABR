classdef Click < abr.sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019
    
    
    properties (Constant)
        Type = 'Click';
    end
    
    methods
        
        % Constructor
        function obj = Click(duration)
            obj.ignoreProcessUpdate = true;
            
            if nargin < 1 || isempty(duration), duration = 0.1; end
            
            obj.duration.Value = duration;
            obj.duration.ValueFormat = '%.3f';
            obj.duration.MaxLength = inf;

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
                if obj.Calibration.calibration_is_valid
                    A_V = obj.calibration.estimate_calibrated_voltage(freq(m),A(a));
                else
                    A_V = 1;
                end

                for d = 1:length(D)
                    y = A_V .* ones(round(obj.Fs*D(d)),1);
                    obj.data{k,1} = y;
                    obj.dataParams.soundLevel(k,1) = A(a);
                    obj.dataParams.duration(k,1)   = D(d);
                    k = k + 1;
                end
            end
            
            % no gating on click stimuli
        end
    end
    
    
end