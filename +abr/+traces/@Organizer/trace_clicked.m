function trace_clicked(h,event,obj,traceIdx) %#ok<INUSL>
fcc = obj.mainFig.CurrentModifier;

thisTrace = obj.Traces(traceIdx);

ax = thisTrace.LineHandle.Parent;
% titleStr = sprintf('%s\n',thisTrace.LabelID);

% titleStr = char(join(c,','));


% ax.Title.String = titleStr;
ax.Title.Color = thisTrace.Color;

if isequal({'shift'},fcc)
    tidx = obj.TraceSelection;
    if isempty(tidx)
        tidx = traceIdx; 
    else
        oy = obj.Traces(tidx).YOffset;
        ny = thisTrace.YOffset;
        if ny < oy
            tidx = find(obj.YOffset <= oy & obj.YOffset >= ny);
        else
            tidx = find(obj.YOffset >= oy & obj.YOffset <= ny);
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
    gid = obj.GroupID;
    ind = gid(traceIdx) == gid;
    obj.TraceSelection = union(obj.TraceSelection,obj.TraceIdx(ind));
    uistack([obj.Traces(obj.TraceSelection).LineHandle],'top');
    uistack([obj.Traces(obj.TraceSelection).MarkerHandles],'top');
    uistack([obj.Traces(obj.TraceSelection).MarkerLabelHandles],'top');
    uistack([obj.Traces(obj.TraceSelection).LabelHandle],'top');
    
    set([obj.Traces(obj.TraceSelection).LabelHandle],'BackgroundColor',[1 1 1 1]);
    
else
    obj.TraceSelection = traceIdx;
end


h = [obj.Traces.LineHandle];
ind = ismember(obj.TraceIdx,obj.TraceSelection)';
fu = arrayfun(@(a) isa(a,'matlab.graphics.primitive.Line'),h);
set(h(~ind&fu),'LineWidth',obj.defaultTraceWidth);
set(h(ind) ,'LineWidth',obj.selectedTraceWidth);
