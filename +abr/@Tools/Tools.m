classdef Tools

    methods (Static)

        
        function s = last_modified_str(datens)
            % s = last_modified_str(datens)
            %
            % Accepts filename, date string, or datenum and returns:
            % 'File last modifed on Sun, May 05, 2019 at 12:19 PM'
            
            narginchk(1,1);
            
            if ischar(datens)
                if exist(datens,'file') == 2
                    d = dir(datens);
                    datens = d(1).date;
                else
                    s = sprintf('File does not exist! "%s"',datens);
                    return
                end
                datens = datenum(datens);
            end
                
            s = sprintf('File last modifed on %s at %s', ...
                datestr(datens,'ddd, mmm dd, yyyy'),datestr(datens,'HH:MM PM'));
        end
        
        function r = validate_filename(ffn)
            ffn = cellstr(ffn);
            r = false(size(ffn));
            for i = 1:numel(ffn)
                [~,fn,ext] = fileparts(ffn{i});
                fn = [fn ext]; %#ok<AGROW>
                r(i) = length(fn) <= 255 ...
                    && length(ffn{i}) <= 32000 ...
                    && isempty(regexp(ffn{i}, ['^(?!^(PRN|AUX|CLOCK\$|NUL|CON|COM\d|LPT\d|\..*)', ...
                    '(\..+)?$)[^\x00-\x1f\\?*:\"><|/]+$'], 'once'));
            end
        end
        
        function str = truncate_str(str,maxn,side)
            if nargin < 3 || isempty(side), side = 'left'; end
            mustBeMember(side,{'left' 'right'});
            str = cellstr(str);
            for i = 1:numel(str)
                if length(str{i}) < maxn
                    str{i} = str{i};
                elseif isequal(lower(side),'right')
                    str{i} = [str{i}(1:end-maxn) '...'];
                else
                    str{i} = ['...' str{i}(end-maxn+1:end)];
                end
            end
        end
        
        function keep_figure_on_top(hFig,state)
            % keep_figure_on_top(hFig,state)
            %
            % Maintain figure (figure handle = hFig) on top of all other windows if
            % state = true.
            %
            % No errors or warnings are thrown if for some reason this function is
            % unable to keep hFig on top.
            %
            % Not likely to work with uifigure objects
                        
            narginchk(2,2);
            assert(ishandle(hFig),'The first input (hFig) must be a valid figure handle');
            assert(islogical(state)||isscalar(state),'The second input (state) must be true (1) or false (0)');
            
            
            drawnow expose
            
            try %#ok<TRYNC>
                warning('off','MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame');
                J = get(hFig,'JavaFrame');
                if verLessThan('matlab','8.1')
                    J.fHG1Client.getWindow.setAlwaysOnTop(state);
                else
                    J.fHG2Client.getWindow.setAlwaysOnTop(state);
                end
                warning('on','MATLAB:HandleGraphics:ObsoletedProperty:JavaFrame');
            end
        end
        
        function [unit,multiplier] = time_gauge(S)
            if S >= 1
                unit = 's';
                multiplier = 1;
                return
            end
            U = {'ps','ns','ms','us','ms','s'};
            U = [U; U; U];
            U = U(:);
            G = [.1; 1; 10] * 10.^(-12:3:3);
            G = G(:);
            M = 10.^(-12:3:3);
            M = [M; M; M];
            M = M(:);
            i = find(G < S*10,1,'last');
            multiplier = 1/M(i);
            unit = U{i};
        end
        
        function [unit,multiplier] = voltage_gauge(V)
            U = {'pV','nV','uV','mV','V','KV','MV','GV'};
            U = [U; U; U];
            U = U(:);
            G = [.1; 1; 10] * 10.^(-12:3:9);
            G = G(:);
            M = 10.^(-12:3:9);
            M = [M; M; M];
            M = M(:);
            i = find(G < V,1,'last');
            if isempty(i), i = 1; end
            multiplier = 1/M(i);
            unit = U{i};
        end
        
        function estr = stack_str(idx)
            d = dbstack;
            dc = dbstack('-completenames');
            if nargin == 0 || isempty(idx), idx = 1; end
            idx = idx + 1; % relative to calling function
            idx(idx > length(d)) = length(d); 
            estr = sprintf(['\tfile:\t<a href="matlab: opentoline(''%s'',%d);">%s (%s)</a>', ...
                '\n\tname:\t%s', ...
                '\n\tline:\t%d'], ...
                dc(idx).file,d(idx).line,d(idx).file,dc(idx).file,d(idx).name,d(idx).line);
        end
    end

end