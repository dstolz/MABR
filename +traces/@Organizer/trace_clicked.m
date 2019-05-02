function trace_clicked(h,event,obj,traceIdx) %#ok<INUSL>
fcc = obj.mainFig.CurrentModifier;


if isequal({'shift'},fcc)
    if traceIdx < min(obj.TraceSelection)
        obj.TraceSelection = union(traceIdx:min(obj.TraceSelection),obj.TraceSelection);
    elseif traceIdx > max(obj.TraceSelection)
        obj.TraceSelection = union(obj.TraceSelection,max(obj.TraceSelection):traceIdx);
    end
    
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
