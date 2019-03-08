classdef Noise < sigdef.Signal
    % Daniel Stolzberg, PhD (c) 2019

    properties (Access = public)
        HPfreq      (:,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 400;
        LPfreq      (:,1) double {mustBeNonempty,mustBePositive,mustBeFinite} = 12000;
        filterOrder (:,1) uint8  {mustBeNonempty,mustBePositive,mustBeInteger} = 20;
    end
    
    properties (Access = private)
        filterDesign
    end
    
    properties (Constant = true, Hidden = true)
        D_HPfreq = 'High-Pass Fc (Hz)';
        D_LPfreq = 'Low-Pass Fc (Hz)';
        D_filterOrder = 'Filter order';
    end
    
    methods
        
        % Constructor
        function obj = Noise(HPfreq,LPfreq,filterOrder)
            if nargin < 1 || isempty(HPfreq), HPfreq = 400; end
            if nargin < 2 || isempty(LPfreq), LPfreq = 12000; end
            if nargin < 3 || isempty(filterOrder), filterOrder = 20; end
            
            obj.HPfreq = HPfreq;
            obj.LPfreq = LPfreq;
            obj.filterOrder = filterOrder;
            
        end
        
        function update(obj)
            obj.filterDesign = designfilt('bandpassfir', ...
                'FilterOrder',     obj.filterOrder, ...
                'CutoffFrequency1',obj.HPfreq, ...
                'CutoffFrequency2',obj.LPfreq, ...
                'SampleRate',      obj.Fs);      
            
%             y = rand(1,obj.N);
%             y = y - mean(y);
            y = randn(1,obj.N);
            y = y ./ max(abs(y));
            
            obj.data = filter(obj.filterDesign,y);
            
            obj.applyGate; % superclass function
        end
        
        function set.HPfreq(obj,f)
            obj.HPfreq = f;
            obj.processUpdate;
        end
        
        function set.LPfreq(obj,p)
            obj.LPfreq = p;
            obj.processUpdate;
        end
    end
    
    
    methods (Static)
        function obj = createDisplay(parent)
            % setup custom fields in some parent figure or panel
        end
    end
    
end