import cloudResultParserTest from './CloudResultParser.test'
import validateNormalizeStepTest from './ValidateNormalizeStep.test'
import classifierTest from './Classifier.test'
import dedupStepTest from './DedupStep.test'
import statsServiceTest from './StatsService.test'
import decoratorsTest from './Decorators.test'
import pipelineTest from './Pipeline.test'

export default function testsuite() {
  cloudResultParserTest()
  validateNormalizeStepTest()
  classifierTest()
  dedupStepTest()
  statsServiceTest()
  decoratorsTest()
  pipelineTest()
}
