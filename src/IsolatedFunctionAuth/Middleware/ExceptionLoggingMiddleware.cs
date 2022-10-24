using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Middleware;
using Microsoft.Extensions.Logging;
using Microsoft.Identity.Client;

namespace IsolatedFunctionAuth.Middleware
{
    public class ExceptionLoggingMiddleware : IFunctionsWorkerMiddleware
    {
        public async Task Invoke(FunctionContext context, FunctionExecutionDelegate next)
        {
            var logger = context.GetLogger(context.FunctionDefinition.Name);
            try
            {
                await next(context);
            }
            catch (MsalException ex)
            {
                logger.LogError(ex, "An authorization error occurred while acquiring a token for downstream API\n" + ex.ErrorCode + "\n" + ex.Message);
                throw;
            }
            catch (Exception ex)
            {
                logger.LogError("Unexpected Error in {FunctionName}: {ExceptionMessage}", context.FunctionDefinition.Name, ex.Message);
                throw;
            }
        }
    }
}
