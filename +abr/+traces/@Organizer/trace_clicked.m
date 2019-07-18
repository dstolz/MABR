function trace_clicked(h,event,obj,traceIdx) %#ok<INUSL>
fcc = obj.mainFig.CurrentModifier;


ax = obj.Traces(traceIdx).LineHandle.Parent;
titleStr = sprintf('%s\n',obj.Traces(traceIdx).LabelID);
c = obj.Traces(traceIdx).LabelText;
for i = 1:length(c)
    titleStr = sprintf('%s%s, ',titleStr,c{i});
end
titleStr(end-1:end) = [];
ax.Title.String = titleStr;
ax.Title.Color = obj.Traces(traceIdx).Color;

if isequal({'shift'},fcc)
    tidx = obj.TraceSelection;
    if isempty(tidx)
        tidx = traceIdx; 
    else
        oy = obj.YPosition(tidx);
        ny = obj.YPosition(traceIdx);
        if ny < oy
            tidx = find(obj.YPosition <= oy & obj.YPosition >= ny);
        else
            tidx = find(obj.YPosition >= oy & obj.YPosition <= ny);
        end
    end
        
    obj.TraceSelection = tidx;
%     if traceIdx < min(obj.TraceSelection)
%         obj.TraceSelection = union(traceIdx:min(obj.TraceSelection),obj.TraceSelection);
%     elseif traceIdx > max(obj.TraceSelection)
%         obj.TraceSelection = union(obj.TraceSelection,max(obj.TraceSelection):traceIdx);
%     end
    
elseif isequal({'control'},fcc)
    ind = obj.TraceSelection == traceIdx;
    if any(ind) && event.Button == 1
        obj.TraceSelection(ind) = []; % deselect
    else
        obj.TraceSelection = [obj.TraceSelection, traceIdx]; % select
    end
    uistack([obj.Traces(obj.TraceSelection).LineHandle],'top');
    uistack([obj.Traces(obj.TraceSelection).MarkerHandles],'top');
    uistack([obj.Traces(obj.TraceSelection).MarkerLabelHandles],'top');
    uistack([obj.Traces(obj.TraceSelection).LabelHandle],'top');
    
    set([obj.Traces(obj.TraceSelection).LabelHandle],'BackgroundColor',[1 1 1 1]);
    
    
elseif isequal({'shift','control'},fcc)
    ind = obj.GroupIdx == obj.GroupIdx(traceIdx);
    obj.TraceSelection = union(obj.TraceSelection,obj.TraceIdx(ind));
    uistack([obj.Traces(obj.TraceSelection).LineHandle],'top');
    uistack([obj.Traces(obj.TraceSelection).MarkerHandles],'top');
    uistack([obj.Traces(obj.TraceSelection).MarkerLabelHandles],'top');
    uistack([obj.Traces(obj.TraceSelection).LabelHandle],'top');
    
    set([obj.Traces(obj.TraceSelection).LabelHandle],'BackgroundColor',[1 1 1 1]);
    
else
    obj.TraceSelection = traceIdx;
end

ind = ismember(obj.TraceIdx,obj.TraceSelection);
set([obj.Traces(~ind).LineHandle],'LineWidth',obj.defaultTraceWidth);
set([obj.Traces(ind).LineHandle] ,'LineWidth',obj.selectedTraceWidth);
