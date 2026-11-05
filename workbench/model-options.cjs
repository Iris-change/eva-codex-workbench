'use strict';
function normalizeModel(model){return {id:model.model,name:model.displayName,isDefault:!!model.isDefault,inputModalities:model.inputModalities||['text','image'],defaultReasoningEffort:model.defaultReasoningEffort||'',supportedReasoningEfforts:(model.supportedReasoningEfforts||[]).map(x=>({reasoningEffort:x.reasoningEffort,description:x.description}))}}
function turnOptions(models,modelId,effort){
 const model=modelId?models.find(x=>x.id===modelId):models.find(x=>x.isDefault)||models[0];
 if(!model)throw Error('所选模型暂不可用，请重新选择');
 if(effort&&!model.supportedReasoningEfforts.some(x=>x.reasoningEffort===effort))throw Error('所选模型不支持这个思考强度');
 return {model,params:{model:model.id,effort:effort||null}};
}
module.exports={normalizeModel,turnOptions};
