{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module TypeChecker where

import Absjavalette
import Printjavalette
import ErrM

import Control.Monad
import Control.Monad.State
import Control.Monad.Trans

import Data.Maybe (fromJust, catMaybes, isNothing)

import Data.Map (Map)
import qualified Data.Map as Map

-- Encapsulate environment in a state monad as to enable error and state handling at the same time 
newtype TCM m a = TCM { unTCM :: StateT Env m a }
    deriving (Monad, MonadTrans, MonadState Env)

-- Type alias to increase readability
type TC a = TCM Err a

-- Replace [(from,to)]
data Env = Env { -- all the type signatures from all the functions
                      signatures :: Map Ident ([Type], Type)
                    , contexts :: [Map Ident Type]
		    , returnType :: Type }

stdFuncs = [(Ident "printInt", ([Int],Void)),
	    (Ident "readInt", ([],Int)),
	    (Ident "printDouble", ([Doub],Void)),
	    (Ident "readDouble", ([],Doub))]	

-- Create an empty environment
emptyEnv :: Env
emptyEnv = Env { signatures = Map.fromList stdFuncs
               , contexts = [Map.empty]
	       , returnType = undefined }

typecheck :: Program -> Err Program
typecheck p = (evalStateT . unTCM) (checkTree p) emptyEnv

-- place one empty context at the top of the stack
pushContext :: TC ()
pushContext = modify (\e -> e { contexts = (Map.empty :  contexts e)})

-- remove topmost context from the stack
popContext :: TC ()
popContext = do
        ctxStack <- gets contexts
        when (null ctxStack) (error "popping from an empty context stack")
        modify (\e -> e { contexts = tail ctxStack })

-- add a variable to current context and fail if it already exists
addVar :: Ident -> Type -> TC ()
addVar n t = do
        env <- get
        let (c:cs) = contexts env
        when (Map.member n c) $ fail $ "adding a variable " ++ (show n) ++ " that is already in top context"
        let c' = Map.insert n t c
        let env' = env { contexts = (c' : cs) }
        put env'

-- add a function definition
addDef :: TopDef -> TC ()
addDef (FnDef retType n as _) = do
	sigs <- gets signatures 
	let ts = map argToType as
	let sigs' = Map.insert n (ts,retType) sigs
	modify (\e -> e { signatures = sigs' } ) -- updates the state record signatures
	where 
	argToType :: Arg -> Type
	argToType (Arg t _) = t

--addDef (FnDef Void printInt 
	
-- Look for a variable in allall the contextss
lookVar :: Ident -> TC Type
lookVar n = do
        ctxs <- gets contexts 
        rtrn (catMaybes ((map (Map.lookup n) ctxs)))
        where
	-- if we cant find anything, make sure we fail
        rtrn :: [Type] -> TC Type
        rtrn [] = fail $ "type of " ++ (show n) ++ " not found"
        rtrn (x:xs) = return x

-- Look for a function in the signatures
lookFun :: Ident -> TC ([Type], Type)
lookFun fName = do
	mbtSig <- gets (Map.lookup fName. signatures)
	when (isNothing mbtSig) (fail $ "Unknown function name")
	return $ fromJust mbtSig
	

inferExp :: Expr -> TC Type
inferExp expr = do
	case expr of
		EVar name 		-> do
			varName <- lookVar name
			return varName
		ELitInt i 		-> return Int 
		ELitDoub d 		-> return Doub
		ELitTrue		-> return Bool
		ELitFalse		-> return Bool
		EApp n expList 		-> do
			(argListTypes,returnType) <- lookFun n
			inferredTypes <- mapM inferExp expList
			when (inferredTypes /= argListTypes) (fail $ "Function " ++ (show n) ++ " passed with incorrect argument types")
			return returnType
		EAppS (Ident "printString") str -> return Void
		EAppS n str		-> do
			(argListTypes,returnType) <- lookFun n
			when (length argListTypes /= 1) (fail $ "Expected 1 parameter for function " ++ (show n)) -- LOL STRING
			return returnType
		Neg expr		-> do
			exprVal <- inferExp expr
			when (exprVal /= Int && exprVal /= Doub) (fail $ "Negation requires either Int or Double. " ++ (show exprVal) ++ " was passed.")
			return exprVal			
		Not expr		-> do
			exprVal <- inferExp expr
			when (exprVal /= Bool) (fail $ "Not expression requires Bool. " ++ (show exprVal) ++ " was passed.")
			return exprVal			
		EMul e0 op e1		-> checkBinaryOperation e0 e1
		EAdd e0 op e1		-> checkBinaryOperation e0 e1
		ERel e0 (EQU) e1 	-> do
			typ0 <- inferExp e0
			typ1 <- inferExp e1
			when (typ0 /= typ1) (fail $ "Trying to compare two expressions with different type (" ++ (show typ0) ++ " and " ++ (show typ1) ++ ")")
			return Bool
		ERel e0 op e1		-> do
			checkBinaryOperation e0 e1
			return Bool
		EAnd e0 e1		-> checkBoolean e0 e1
		EOr e0 e1		-> checkBoolean e0 e1
		

-- Check unary numeric operations such as ++ (exp)
checkUnaryOperation :: Expr -> TC Type
checkUnaryOperation exp = do
		iType <- inferExp exp
		if elem iType [Int, Doub] 
			then return iType 
			else fail $ (show iType) ++ "invalid expression" 

-- Check binary numeric operations 
checkBinaryOperation :: Expr -> Expr -> TC Type
checkBinaryOperation e0 e1 = do 
		iType0 <- inferExp e0
		iType1 <- inferExp e1
		if (iType0 == iType1 && iType0 /= Bool && iType0 /= Void)
			then return iType0
			else fail $ "Arithmetic operation have different (or invalid) argument types: " ++ (show iType0) ++ "," ++ (show iType1) 

checkComparator :: Expr -> Expr -> TC Type
checkComparator e0 e1 = do
		iType0 <- inferExp e0
		iType1 <- inferExp e1
		if iType0 == iType1
			then return Bool
			else fail $ "Cannot compare " ++ (show iType0) ++ " with " ++ (show iType1)
		
checkBoolean :: Expr -> Expr -> TC Type
checkBoolean e0 e1 = do
		iType0 <- inferExp e0
		iType1 <- inferExp e1
		if iType0 == Bool && iType1 == Bool
			then return Bool
			else fail $ "Boolean operation has different argument types: " ++ (show iType0) ++ "," ++ (show iType1)

checkStm :: Stmt -> TC Stmt
checkStm stm = do
	case stm of
		Empty 			-> return Empty
		BStmt (Block stmts) 	-> do
			pushContext
			stmts' <- mapM (checkStm) stmts
			popContext
			return (SType Void (BStmt (Block stmts')))
			
		Decl  t itmList		-> do
			mapM_ (addItem t) itmList
			return (SType t stm)
			where
				addItem :: Type -> Item -> TC ()
				addItem t (Init name expr) = do
					exprtype <- inferExp expr
					when (t /= exprtype) (fail $ "Trying to assign variable " ++ (show name) ++ " (which has type " ++ (show t) ++ ") with an expression of type " ++ (show exprtype))
					addVar name t
 
				addItem t (NoInit name) = addVar name t
			
		Ass name epxr		-> do
		  vartype <- lookVar name
		  exptype <- inferExp epxr
		  if vartype == exptype
		    then return (SType vartype stm)
		    else fail $ "Trying to assign " ++ (show name) ++ " (which has type " ++ (show vartype) ++ ") with an expression of type " ++ (show exptype)
		    
		Incr name		-> do
		  typ <- lookVar name
		  if typ == Int
		    then return (SType typ stm)
		    else fail $ "Trying to increment " ++ (show name) ++ ", which has type " ++ (show typ)
		    
		Decr name		-> do
		  typ <- lookVar name
		  if typ == Int
		    then return (SType typ stm)
		    else fail $ "Trying to decrement " ++ (show name) ++ ", which has type " ++ (show typ)
		    
		Ret  expr     		-> do
		  rettype <- gets returnType
		  exptype <- inferExp expr
		  if rettype == exptype
		    then return (SType rettype stm)
		    else fail $ "Trying to return with type " ++ (show exptype) ++ " in a function with type " ++ (show rettype)
		  
		VRet     		-> do
		  rettype <- gets returnType
		  if rettype == Void
		    then return (SType Void stm)
		    else fail $ "Trying to return void in a function of type: " ++ (show rettype)
		    
		Cond expr stmt		-> do
		  exptype <- inferExp expr
		  when (exptype /= Bool) (fail $ "Conditional expression for if-else-statement  not of boolean type: " ++ (show exptype))
		  stmt' <- checkStm stmt
		  return (SType Void (Cond expr stmt'))
		    
		CondElse  expr ifs els  -> do
			exptype <- inferExp expr
			when (exptype /= Bool) (fail $ "Conditional expression for if-statement not of boolean type: " ++ (show exptype))
			ifs' <- checkStm ifs
			els' <- checkStm els
			return (SType Void (CondElse expr ifs' els'))
		  
		While expr stmt		->   do
  		  exptype <- inferExp expr
  		  when (exptype /= Bool) (fail $ "Conditional expression for while-statement not of boolean type: " ++ (show exptype))
  		  stmt' <- checkStm stmt
  		  return (SType Void (While expr stmt'))
  		  
		SExp exprs		-> do
		  typ <- inferExp exprs
		  return (SType typ stm)
		

checkDefReturn :: TopDef -> TC ()
checkDefReturn (FnDef Void _ _ _) = return ()
checkDefReturn fun@(FnDef rettype n _ (Block stms)) = do
	let has_return = any checkStmReturn stms
	if (has_return)
		then return ()
		else fail $ "Function " ++ (show n) ++ " does not return!"

checkStmReturn :: Stmt -> Bool
checkStmReturn (Ret _)                = True
checkStmReturn (VRet)                 = True
checkStmReturn (BStmt (Block stms))   = any checkStmReturn stms
checkStmReturn (Cond exp stm)         = case checkExpBool exp of
																					True  -> checkStmReturn stm
																					False -> False
checkStmReturn (CondElse exp stm1 stm2) = (checkStmReturn stm1) && (checkStmReturn stm2)
checkStmReturn _ = False

checkExpBool :: Expr -> Bool
checkExpBool ELitTrue     = True
checkExpBool ELitFalse    = False
checkExpBool (EAnd e1 e2) = (checkExpBool e1) && (checkExpBool e2)
checkExpBool (EOr e1 e2)  = (checkExpBool e1) || (checkExpBool e2)
checkExpBool _            = False

checkDef :: TopDef -> TC TopDef
checkDef fun@(FnDef retType name args (Block stms)) = do
	pushContext
	modify (\e -> e { returnType = retType } )
	mapM_ addArgs args  
	newstms <- mapM checkStm stms
	popContext
	checkDefReturn fun
	return (FnDef retType name args (Block newstms))
	where
	addArgs :: Arg -> TC ()
	addArgs (Arg t i) = addVar i t

checkTree :: Program -> TC Program
checkTree (Program defs) = do
	mapM addDef defs
	newdefs <- mapM checkDef defs
	return (Program newdefs)
