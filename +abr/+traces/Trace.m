classdef Trace < handle & matlab.mixin.SetGet
    % TRACE   Class for handling and analyzing ABR trace data
    %
    %   The Trace class encapsulates data and methods related to Auditory
    %   Brainstem Response (ABR) traces, providing functionalities for
    %   data management, plotting, and analysis.
    %
    % Trace Properties:
    %   ID                  - Unique identifier for the trace (uint32)
    %   GroupID             - Identifier for the group to which the trace belongs (uint32)
    %   YOffset             - Vertical offset applied to the trace data (double)
    %   ABR                 - ABR object containing auditory response data (abr.ABR)
    %   Color               - RGB color specification for plotting the trace ([0 0 0])
    %   Alpha               - Transparency level of the trace plot (double, 0 to 1)
    %   LineWidth           - Width of the trace line in plots (double)
    %   Marker              - Array of Marker objects associated with the trace (abr.traces.Marker)
    %   TimeUnit            - Unit of time for the trace ('auto', 's', 'ms', 'us', 'ns')
    %   RawData             - Buffer object containing raw data (abr.Buffer)
    %   Analysis            - Analysis object associated with the trace
    %   LabelText           - Text label for the trace
    %   Props               - Structure containing additional properties (struct, read-only)
    %   LabelID             - Character identifier for the trace label (char, read-only)
    %
    % Trace Dependent Properties:
    %   TimeVector          - Time vector corresponding to the trace data
    %   N                   - Number of data points in the trace
    %   LineHandleIsValid   - Logical indicating if the line handle is valid
    %   LabelHandleIsValid  - Logical indicating if the label handle is valid
    %   Units               - Structure containing unit information
    %   Data                - Processed trace data
    %   FirstTimepoint      - Time of the first data point
    %   SampleRate          - Sampling rate of the trace data
    %
    % Trace Methods:
    %   Trace               - Constructor to create a Trace object
    %   delete              - Destructor to clean up resources
    %   plot                - Method to plot the trace data
    %   line                - Method to create a line object for the trace
    %
    % Example:
    %   abrObj = abr.ABR(); % Create an ABR object
    %   traceObj = abr.traces.Trace(abrObj); % Create a Trace object
    %   traceObj.plot(); % Plot the trace data
    %
    % See also: abr.ABR, abr.traces.Marker, abr.Buffer
    properties
        ID              (1,1) uint32 = 1;
        GroupID         (1,1) uint32 = 1;

        YOffset         (1,1) double {mustBeFinite} = 0;


        ABR             (1,1) abr.ABR

        Color           (1,3) double {mustBeNonnegative,mustBeLessThanOrEqual(Color,1)} = [0 0 0];
        Alpha           (1,1) double {mustBePositive,mustBeLessThanOrEqual(Alpha,1)} = 1; % 0 = clear; 1 = opaque
        LineWidth       (1,1) double {mustBePositive,mustBeFinite} = 1;

        Marker          (:,1) abr.traces.Marker

        TimeUnit        (1,:) char {mustBeMember(TimeUnit,{'auto','s','ms','us','ns'})} = 'auto';

        RawData         (1,1) abr.Buffer

        Analysis        (1,1) % abr.analysis

        LabelText
    end

    properties (SetAccess = private)
        Props   (1,1) struct
        LabelID   (1,:) char
    end

    properties (Dependent)
        TimeVector
        N
        LineHandleIsValid
        LabelHandleIsValid
        Units (1,1) struct % same fields as props

        Data
        FirstTimepoint
        SampleRate
    end

    properties (SetAccess = private, Transient)
        LineHandle      (1,1)
        LabelHandle     (1,1)

        MarkerHandles       (1,:)
        MarkerLabelHandles  (1,:)

        Parent
    end

    methods
        % Constructor
        %function obj = Trace(data,SIG,firstTimepoint,Fs)
        function obj = Trace(ABR)
            if nargin == 0
                obj.ID = 0;
                return
            end

            obj.ABR = copy(ABR);
        end

        % Destructor
        function delete(obj)
            for i = 1:length(obj)
                try
                    delete(obj(i).LineHandle);
                end
                try
                    delete(obj(i).LabelHandle);
                end
            end
            try
                delete(obj);
            end
        end

        function d = get.Data(obj)

            d = obj.ABR.ADC.SweepMean;

        end

        function fs = get.SampleRate(obj)
            fs = obj.ABR.ADC.SampleRate;
        end

        function p = get.FirstTimepoint(obj)
            p = obj.ABR.adcWindow(1);
        end

        function str = get.LabelID(obj)
            gid = obj.GroupID;
            k = 2;
            while gid(1) > 26
                gid(end+1) = mod(gid(k-1),26);
                if gid(end) == 0, gid(end) = 26; end
                gid(k-1) = gid(k-1) - 26;
            end
            gid = gid+64;
            str = sprintf('%s-%d',gid,obj.ID);
        end

        function str = get.LabelText(obj)
            if isempty(obj.LabelText)
                str = obj.ABR.SIG.Label;
                str{end+1} = sprintf('N = %d',obj.ABR.ADC.NumSweeps);
            else
                str = obj.LabelText;
            end

        end

        function t = get.TimeVector(obj)
            t = 0:1/obj.SampleRate:obj.N/obj.SampleRate-1/obj.SampleRate;
            t = t + obj.FirstTimepoint;
        end

        function n = get.N(obj)
            n = length(obj.Data);
        end

        function p = get.Parent(obj)
            p = obj.LineHandle.Parent;
        end

        function createLineHandleIfNone(obj)
            if ~obj.LineHandleIsValid, plot(obj); end
        end

        function v = get.LineHandleIsValid(obj)
            try
                v = isvalid(obj.LineHandle);
            catch
                v = false;
            end
        end

        function v = get.LabelHandleIsValid(obj)
            try
                v = isvalid(obj.LabelHandle);
            catch
                v = false;
            end
        end

        function h = get.MarkerHandles(obj)
            h = [obj.Marker.MarkerHandle];
        end

        function h = get.MarkerLabelHandles(obj)
            h = [obj.Marker.LabelHandle];
        end

        % Overloaded Functions --------------------------------------------
        function plot(obj,ax)
            if nargin < 2 || isempty(ax), ax = gca; end

            for kobj = obj
                if kobj.LineHandleIsValid
                    h = kobj.LineHandle;
                else
                    h = line(kobj,ax);
                end

                kobj.LineHandle = h;

                h.Color = kobj.Color;


                % label
                x = h.XData(1);

                x = x - .3;
                y = double(max(kobj.Data) + mean(kobj.LineHandle.YData));
                if kobj.LabelHandleIsValid
                    t = kobj.LabelHandle;
                else
                    t = text(ax,x,y,kobj.LabelText);
                end
                t.Position = [x y];
                %t.String = kobj.LabelID;
                t.String = kobj.LabelText;
                t.Color = max(kobj.Color-.2,0);
                t.FontWeight = 'bold';
                %                 t.BackgroundColor = [ax.Color 0.9];
                t.BackgroundColor = 'none';
                t.Margin = 0.1;
                t.HorizontalAlignment = 'right';
                t.VerticalAlignment   = 'baseline';
                kobj.LabelHandle = t;

            end

        end

        function h = line(obj,ax)
            h = line(ax,nan,nan);

            x = obj.TimeVector;

            tu = obj.TimeUnit;

            if isequal(tu,'auto')
                mx = x(end);
                if mx > 1
                    tu = 's';
                elseif mx <= 1
                    tu = 'ms';
                elseif mx <= .01
                    tu = 'us';
                elseif mx <= 0.001
                    tu = 'ns';
                end
            end

            switch tu
                case 'ms'
                    x = x .* 1e3; % s -> ms
                case 'us'
                    x = x .* 1e6; % s -> us
                case 'ns'
                    x = x .* 1e9; % s -> ns
            end

            h.XData = x;
            h.YData = obj.Data;
            h.Color = obj.Color;

            ax.XAxis.Label.String = sprintf('time (%s)',tu);
        end


    end
end