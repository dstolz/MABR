classdef Progress < handle
% mabr.analysis.Progress  Minimal console progress reporter.
%
%   A self-contained stand-in for parfor_progress: no temp file, no path
%   dependency, and silent when it is switched off. It exists so that the
%   analysis classes can report progress on a long loop without dragging a
%   File Exchange dependency into the toolbox.
%
%   p = mabr.analysis.Progress(n,"Extracting")   % n steps
%   p.step()                                     % advance one step
%   p.close()                                    % finish the line
%
%   Progress(n,msg,false) is a no-op object, which is what lets a caller
%   write the same three lines whether or not the user asked for output.
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
        Width   (1,1) double = 0    % characters printed by the last update
        Started (1,1) uint64 = 0
        Done    (1,1) logical = false
    end

    methods
        function obj = Progress(total,message,enabled)
            % Progress(total,message,enabled) starts a new progress line.
            %
            %   total    number of steps expected (0 disables output)
            %   message  text shown before the bar/summary (default "")
            %   enabled  whether to print anything at all (default true)
            %   obj      (returned) the Progress object
            arguments
                total   (1,1) double {mustBeNonnegative} = 0
                message (1,1) string = ""
                enabled (1,1) logical = true
            end
            obj.Total   = total;
            obj.Message = message;
            obj.Enabled = enabled && total > 0;
            obj.Started = tic;
            obj.draw();
        end

        function step(obj,n)
            % Advance the counter by n steps (default 1) and redraw.
            %
            %   n  steps to advance (default 1); (no return value)
            arguments
                obj
                n (1,1) double = 1
            end
            obj.Count = min(obj.Total, obj.Count + n);
            obj.draw();
        end

        function close(obj)
            % Finish the line. Safe to call more than once.
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
            if seconds < 60
                s = sprintf('%.1f s', seconds);
            elseif seconds < 3600
                s = sprintf('%d m %02.0f s', floor(seconds/60), mod(seconds,60));
            else
                s = sprintf('%d h %02.0f m', floor(seconds/3600), mod(seconds,3600)/60);
            end
        end
    end
end
