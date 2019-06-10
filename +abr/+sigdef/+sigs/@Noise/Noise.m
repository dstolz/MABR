classdef Noise < abr.sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019

    properties (Access = public)
        HPfreq          (1,1) abr.sigdef.sigProp
        LPfreq          (1,1) abr.sigdef.sigProp
        filterOrder     (1,1) abr.sigdef.sigProp
        seed            (1,1) abr.sigdef.sigProp
    end
    

    properties (Access = private)
        filterDesign
    end
    
    
    properties (Constant)
        Type = 'Noise';
    end
    
    methods
        
        % Constructor
        function obj = Noise(HPfreq,LPfreq,filterOrder)
            obj.ignoreProcessUpdate = true;

            if nargin < 1 || isempty(HPfreq),       HPfreq = 4;       end
            if nargin < 2 || isempty(LPfreq),       LPfreq = 20;      end
            if nargin < 3 || isempty(filterOrder),  filterOrder = 20; end
            
            
            obj.HPfreq       = abr.sigdef.sigProp(HPfreq,'High-Pass Fc','kHz',1000);
            obj.HPfreq.Alias = 'HP Freq';
            obj.HPfreq.ValueFormat = '%.3f';
            
            obj.LPfreq       = abr.sigdef.sigProp(LPfreq,'Low-Pass Fc','kHz',1000);
            obj.LPfreq.Alias = 'LP Freq';
            obj.LPfreq.ValueFormat = '%.3f';
            
            obj.filterOrder  = abr.sigdef.sigProp(filterOrder,'Filter order');
            obj.filterOrder.Alias = 'Filt Order';
            obj.filterOrder.ValueFormat = '%d';
            
            obj.seed       = abr.sigdef.sigProp(0,'Seed#; 0 = "shuffle"');
            obj.seed.Alias = 'Seed';
            
            obj.SortProperty = 'HPfreq';
            
            obj.informativeParams = {'HPfreq','LPfreq','soundLevel'};

            obj.ignoreProcessUpdate = false;

        end
        
        function obj = update(obj)
            obj.filterDesign = designfilt( ...
                'bandpassfir', ...
                'FilterOrder',     obj.filterOrder.realValue, ...
                'CutoffFrequency1',obj.HPfreq.realValue, ...
                'CutoffFrequency2',obj.LPfreq.realValue, ...
                'SampleRate',      obj.Fs);      
            
            if obj.seed.realValue == 0
                rng('shuffle');
            else
                rng(obj.seed);
            end
            
            y = randn(1,obj.N);
            y = y ./ max(abs(y));
            
            obj.data = filter(obj.filterDesign,y);
            
            A = obj.soundLevel.realValue;
            Adb = CALVOLT.*10.^((A(a)-CALVAL)./20);
            obj.applyGate; % superclass function
        end
        
        function obj = set.HPfreq(obj,value)
            if isa(value,'abr.sigdef.sigProp')
                obj.HPfreq = value;
            else
                mustBePositive(value);
                mustBeFinite(value);
                mustBeNonempty(value);
                obj.HPfreq.Value = value;
                obj.processUpdate;
            end
        end
        
        function obj = set.LPfreq(obj,value)
            if isa(value,'abr.sigdef.sigProp')
                obj.LPfreq = value;
            else
                mustBePositive(value);
                mustBeFinite(value);
                mustBeNonempty(value);
                obj.LPfreq.Value = value;
                obj.processUpdate;
            end
        end
        
        
    end
    
    
    
end