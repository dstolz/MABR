function key_processor(hFig,KeyData,obj,Cmd) %#ok<INUSL>

if nargin == 4 && ischar(Cmd)
    K = Cmd;
    M = 'control';
else
    K = KeyData.Key;
    M = KeyData.Modifier;
end

if isempty(K) || ismember(K,{'control','shift'}), return; end

tidx = obj.TraceSelection;


if isequal(M,{'shift','control'})
    
    % ignore some basic Figure commands
    if any(ismember(K,{'d','u','p'})), return; end
    
    
elseif isequal(char(M),'control')
    % apply to selected trace
    
else
    return
end

switch lower(K)
    
    
    case {'a','all'} % toggel selection of all traces
        if obj.N ~= length(tidx) % select all
            obj.TraceSelection = obj.TraceIdx;
            set([obj.Traces.LineHandle] ,'LineWidth',obj.selectedTraceWidth);
        else % deselect all
            obj.TraceSelection = [];
            set([obj.Traces.LineHandle] ,'LineWidth',obj.defaultTraceWidth);
        end
        
    case {'c','clear'} % clear all traces without prompt
        r = questdlg('Are you sure you want to clear all of the traces?', ...
            'Clear Traces','Clear','Cancel','Cancel');
        if isequal(r,'Cancel'), return; end
        obj.clear;
        
    case {'d','delete'} % delete selected traces
        if isempty(tidx), return; end
        obj.delete_trace(tidx);
        plot(obj);
        
    case {'e','export'} % export selected trace(s)
        if isempty(tidx), return; end
        ev = evalin('base','whos(''TraceData*'')');
        if isempty(ev)
            id = 1;
        else
            id = max(cellfun(@(a) str2double(a(find(a=='_',1,'last')+1:end)),{ev.name}))+1;
        end
        
        for i = 1:length(tidx)
            T(i).Time = obj.Traces(tidx(i)).TimeVector;
            T(i).Data = obj.Traces(tidx(i)).Data;
            T(i).SampleRate = obj.Traces(tidx(i)).SampleRate;
%             T(i).RawData = obj.Traces(tidx(i)).RawData;
            T(i).Color = obj.Traces(tidx(i)).Color;
            T(i).LineWidth = obj.Traces(tidx(i)).LineWidth;
            T(i).LabelText = obj.Traces(tidx(i)).LabelText;
        end
        assignin('base',sprintf('TraceData_%d',id),T);
        evalin('base',sprintf('whos TraceData_%d',id))
        commandwindow;
        
    case {'f','savefig'}
        dfltpn = getpref('TraceOrganizer','dfltimgpth',cd);
%         [fn,pn,ext] = uiputfile({'.jpg';'.png';'.eps';'.pdf';'.bmp';'.emf'; ...
%             '.pbm';'.pcx';'.pgm';'.ppm';'.tif', ...
%             'Image File (*.jpg,*.png,*.eps,*.pdf,*.bmp,*.emf,*.pbm,*.pcx,*.pgm,*.ppm,*.tif)'}, ...
%             'Save as Image', dfltpn);
        [fn,pn,fidx] = uiputfile({ ...
            '.jpg','jpeg (*.jpg)'; ...
            '.png','png (*.png)'; ...
            '.tif','tiff (*.tif)'; ...
            '.tif','tiffn (*.tif)'; 
            '.pdf','pdf (*.pdf)'; ...
            '.eps','eps (*.eps)'; ...
            '.eps','epsc (*.eps)'; ...
            '.svg','svg (*.svg)'}, ...
            'Export as Image',dfltpn);

        if isequal(pn,0), return; end
        
        f = {'jpeg','png','tiff','tiffn','pdf','eps','epsc','svg'};
        
        saveas(obj.mainFig,fullfile(pn,fn),f{fidx});
        
        
        
    case {'g','group'} % group selected traces
        if isempty(tidx), return; end
        obj.GroupIdx(tidx) = max(obj.GroupIdx) + 1;
        plot(obj);
        
    case {'h','hide'} % toggle hiding labels
        h = [obj.Traces.LabelHandle];
        if isempty(tidx), tidx = obj.TraceIdx; end
        if isequal(h(tidx(1)).Visible,'on')
            set(h(tidx),'visible','off');
        else
            set(h(tidx),'visible','on');
        end
        
    case {'i','equal'}
        if length(tidx) < 2, tidx = obj.TraceIdx; end
        y = obj.YPosition(tidx);
        obj.YPosition(tidx) = linspace(min(y),max(y),length(tidx));
        plot(obj);
        
        
    case 'j' % increase trace amp
        obj.YScaling = obj.YScaling * 1.1;
        plot(obj);

    case 'k' % increase trace spacing
        if length(tidx) < 2, return; end
        y = obj.YPosition(tidx);
        [y,i] = sort(y,'ascend');
        tidx = tidx(i);
        dy = y - y(1);
        ny = y + dy * .1;
        obj.YPosition(tidx) = ny;
        plot(obj);
        
    case 'm' % decrease trace spacing
        if length(tidx) < 2, return; end
        y = obj.YPosition(tidx);
        [y,i] = sort(y,'ascend');
        tidx = tidx(i);
        dy = y - y(1);
        ny = y - dy * .1;
        obj.YPosition(tidx) = ny;
        plot(obj);
        
    case 'n' % decrease trace amp
        obj.YScaling = obj.YScaling * 0.9;
        plot(obj);
        
    case {'o','load'} % load a saved file
        load(obj);
        
    case {'p','popout'} % popout selected traces
        if isempty(tidx), return; end
        T = abr.traces.Organizer(obj.Traces(tidx));
        
        figure(T);
        plot(T);
        
    case {'s', 'save'} % save trace organizer
        save(obj);
        
    case {'u','ungroup'} % ungroup selected traces
        if isempty(tidx), return; end
        obj.GroupIdx(tidx) = 1; % reset to default group
        plot(obj);
        
    case {'v','overlap'} % overlap selected traces
        if isempty(tidx), return; end
        if all(obj.YPosition(tidx) == obj.YPosition(tidx(1)))
            %                         obj.YPosition(tidx)
        else
            obj.YPosition(tidx) = obj.YPosition(tidx(1));
        end
        plot(obj);
        
    case {'q','color'} % change color of selected trace
        if isempty(tidx), return; end
        
        
        
    case {'?','slash'} % list commands
        obj.display_info;
        
        
end
