classdef Progress < handle
% mabr.analysis.Progress  Minimal console progress reporter with an optional sink.
%
%   A self-contained stand-in for parfor_progress: no temp file, no path
%   dependency, and silent when it is switched off. It exists so that the
%   analysis classes can report progress on a long loop without dragging a
%   File Exchange dependency into the toolbox.
%
%   p = mabr.analysis.Progress(n,"Extracting")          % n steps, console
%   p = mabr.analysis.Progress(n,"Extracting",false,fcn)% silent console, sink fcn
%   p.step()                                            % advance one step
%   p.close()                                           % finish the line
%
%   Progress(n,msg,false) is a no-op object as far as the console goes, which
%   is what lets a caller write the same three lines whether or not the user
%   asked for output.
%
%   THE SINK is how a GUI hears about a long step and how it CANCELS one. It is
%   a function handle fcn(message,count,total), passed explicitly -- there is
%   no global or persistent sink anywhere, so two sessions working at once can
%   never report into each other's progress bar. It is called
%     - once at construction (count 0),
%     - from step() when at least 0.1 s has passed since the last call, or
%       when count reaches total (so the last step is always reported),
%   whether or not console output is enabled, and NEVER from close() or the
%   destructor: an error thrown by the sink propagates out of step() -- which
%   is exactly how a GUI cancels, by making its sink throw
%   MException('mabr:analysis:cancelled','Cancelled by user.') -- and an error
%   inside a destructor would be swallowed and turned into a warning.
%
%   Nothing here is required for correctness -- delete every call and the
%   analysis is unchanged.
%
%   See also mabr.analysis.Session

    properties (SetAccess = private)
        Total   (1,1) double = 0
        Count   (1,1) double = 0
        Message (1,1) string = ""
        Enabled (1,1) logical = true
    end

    properties (Access = private)
        Width    (1,1) double = 0    % characters printed by the last update
        Started  (1,1) uint64 = 0
        Done     (1,1) logical = false
        Sink     = []                % @(message,count,total), or []
        LastSink (1,1) uint64 = 0    % tic of the last sink call
    end

    properties (Constant)
        % Shortest interval between two sink calls from step(), seconds. A
        % per-file loop runs hundreds of steps a second, and a GUI that
        % repainted a progress bar for every one would spend its time there.
        SinkInterval = 0.1
    end

    methods
        function obj = Progress(total,message,enabled,sink)
            % Progress(total,message,enabled,sink) starts a new progress line.
            %
            %   total    number of steps expected (0 disables console output)
            %   message  text shown before the bar/summary (default "")
            %   enabled  whether to print anything at all (default true)
            %   sink     [] (default) or a function handle
            %            fcn(message,count,total), called as the class help
            %            describes; an error it throws propagates
            %   obj      (returned) the Progress object
            arguments
                total   (1,1) double {mustBeNonnegative} = 0
                message (1,1) string = ""
                enabled (1,1) logical = true
                sink = []
            end
            if ~isempty(sink) && ~isa(sink,'function_handle')
                error('mabr:analysis:Progress:sink', ...
                    'A progress sink is a function handle fcn(message,count,total), or [].');
            end
            obj.Total   = total;
            obj.Message = message;
            obj.Enabled = enabled && total > 0;
            obj.Sink    = sink;
            obj.Started = tic;
            obj.draw();
            obj.callSink();             % count 0: the step has started
        end

        function step(obj,n)
            % Advance the counter by n steps (default 1), redraw, and report.
            %
            %   n  steps to advance (default 1); (no return value)
            %
            %   An error thrown by the sink propagates from here.
            arguments
                obj
                n (1,1) double = 1
            end
            obj.Count = min(obj.Total, obj.Count + n);
            obj.draw();
            if obj.Done || isempty(obj.Sink), return; end
            if obj.Count >= obj.Total || toc(obj.LastSink) >= mabr.analysis.Progress.SinkInterval
                obj.callSink();
            end
        end

        function close(obj)
            % Finish the line. Safe to call more than once. Never calls the sink.
            if obj.Done, return; end
            obj.Done = true;
            if ~obj.Enabled, return; end
            obj.erase();
            fprintf('%s: %d/%d done in %s\n', obj.Message, obj.Count, ...
                obj.Total, mabr.analysis.Progress.duration(toc(obj.Started)));
            obj.Width = 0;
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function callSink(obj)
            % Report to the sink, if there is one. The clock restarts BEFORE
            % the call, so a sink that takes a while to paint does not make
            % the next step report again immediately.
            if isempty(obj.Sink), return; end
            obj.LastSink = tic;
            obj.Sink(obj.Message,obj.Count,obj.Total);
        end

        function draw(obj)
            if ~obj.Enabled || obj.Done, return; end
            frac = obj.Count / max(1,obj.Total);
            nbar = 20;
            bar  = [repmat('=',1,round(frac*nbar)) repmat(' ',1,nbar-round(frac*nbar))];
            txt  = sprintf('%s [%s] %d/%d', obj.Message, bar, obj.Count, obj.Total);
            obj.erase();
            fprintf('%s', txt);
            obj.Width = numel(txt);
        end

        function erase(obj)
            if obj.Width > 0
                fprintf('%s', repmat(char(8),1,obj.Width));   % backspaces
                fprintf('%s', repmat(' ',1,obj.Width));
                fprintf('%s', repmat(char(8),1,obj.Width));
            end
            obj.Width = 0;
        end
    end

    methods (Static)
        function s = duration(seconds)
            % Human-readable elapsed time.
            %
            %   seconds  elapsed time, scalar seconds
            %   s        (returned) 1x1 char, e.g. "1.2 s", "3 m 04 s", "1 h 02 m"
            % Rounded to the unit shown BEFORE it is split, so 119.7 s reads
            % "2 m 00 s" rather than "1 m 60 s".
            if seconds < 59.95
                s = sprintf('%.1f s', seconds);
            elseif seconds < 3599.5
                k = round(seconds);
                s = sprintf('%d m %02d s', floor(k/60), mod(k,60));
            else
                k = round(seconds/60);
                s = sprintf('%d h %02d m', floor(k/60), mod(k,60));
            end
        end
    end
end
