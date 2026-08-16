I want to create a new set of agent plugins for securing an AI-first SDLC.

I'm taking inspiration from this anthropic blog:
https://claude.com/blog/how-anthropic-secures-its-ai-native-software-development-lifecycle

My principle is to use well maintained and open source skills/tools vs floating our own, unless otherwise needed and proven through evaluations.


The existing skills I would like to use:

Plan/Code phase - use Project Codeguard for providing secure-by-design rules for code generation, customized for an applicaiton.  We should look at it and ensure we're following an LLM Wiki approach with progressive disclosure, i'm not sure how it actually installs as rules or skills to use JIT while agent is coding.  I think a clean way to do it would be to give the skill instructions to use the tool (in the description) when planning a new feature implementation to ensure secure-by-design principles are being followed for generating the code to pre-empt the AI to write secure code. the result should be a plan/spec that is compliant and secure -> think of this as a Secure Build Plan to augment normal build plans.  

Test - application quality/performance - First skill is for core evaluations using Promptfoo eval to set up core evaluation tests - benign evals to test the performance of the application and establish a benchmark.  In addition we should add in core single-prompt that also test for common metrics related to AI systems (i'm not an eval expert so you'll have to provide).  I also want to add in other metrics related to cybersecurity using best-of-the-best benchmark/eval sets as of  August 2026 for cyber security related evals - i'm thinking here evals like in cyberseceval4 or b3 or others which I think are single-prompt based.  

Test adversarial (AI specific; DAST like) - use promptoo redteam to do multi-turn objective attacks based on the users application and what good tests woudl be.

Test adversarial (broader pen test; DAST like) - use the https://github.com/usestrix/strix open source pentesting capability and build as a skill, also include the core skills I believe it comes with.  

Test - Code review local (SAST) - keep this tool agnostic, and recommend using foundation models directly with a well-formed prompt to conduct a thorough code scan.  You should not tell it specifics for exactly what types of common code security issues to find (don't add specific CWEs), but instead keep it higher level - tell it to first create a list of the common types of code related security issues to scan and review, given the context of the app.  Don't lock the skill into only looking at specific things in other words - we wnat the AI to use it's brains to find unknown unknowns using its full knowledge.  We are just giving it implicit instructions to scan and profile the code, propose the categories of security issues to do deep dives into, do the scanning, and then write out the results as a normal code scanner would with severity levels/code lines and snippets/description/remediation guidance.

Test - Code review CI/CD (SAST) - configure a CodeQL config to run for that specific application so next push will run.  This skill should also know how to read the results back 

Remediation - take all of the testing results and remediate the issues and fix the code.

I want to package this up using the new agent plugins framework:
https://developers.googleblog.com/agent-plugins-package-your-skills-tools-and-more/


