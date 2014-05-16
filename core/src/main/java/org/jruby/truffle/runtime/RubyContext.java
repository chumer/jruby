/*
 * Copyright (c) 2013 Oracle and/or its affiliates. All rights reserved. This
 * code is released under a tri EPL/GPL/LGPL license. You can use it,
 * redistribute it and/or modify it under the terms of the:
 *
 * Eclipse Public License version 1.0
 * GNU General Public License version 2
 * GNU Lesser General Public License version 2.1
 */
package org.jruby.truffle.runtime;

import java.io.*;
import java.math.*;
import java.util.concurrent.atomic.*;

import org.jruby.Ruby;
import org.jruby.*;
import com.oracle.truffle.api.*;
import com.oracle.truffle.api.frame.*;
import com.oracle.truffle.api.nodes.*;
import com.oracle.truffle.api.source.*;
import org.jruby.runtime.builtin.IRubyObject;
import org.jruby.truffle.runtime.control.*;
import org.jruby.truffle.runtime.core.*;
import org.jruby.truffle.runtime.core.RubyBinding;
import org.jruby.truffle.runtime.core.RubyModule;
import org.jruby.truffle.runtime.core.RubyString;
import org.jruby.truffle.runtime.core.RubySymbol;
import org.jruby.truffle.runtime.core.RubyBasicObject;
import org.jruby.truffle.runtime.subsystems.*;
import org.jruby.truffle.runtime.debug.RubyDebugManager;
import org.jruby.truffle.translator.TranslatorDriver;
import org.jruby.util.ByteList;

/**
 * The global state of a running Ruby system.
 */
public class RubyContext {

    private final Ruby runtime;
    private final TranslatorDriver translator;
    private final CoreLibrary coreLibrary;
    private final FeatureManager featureManager;
    private final ObjectSpaceManager objectSpaceManager;
    private final TraceManager traceManager;
    private final ThreadManager threadManager;
    private final FiberManager fiberManager;
    private final AtExitManager atExitManager;
    private final RubyDebugManager rubyDebugManager;
    private final SourceManager sourceManager;
    private final RubySymbol.SymbolTable symbolTable = new RubySymbol.SymbolTable(this);

    private AtomicLong nextObjectID = new AtomicLong(0);

    public RubyContext(Ruby runtime, TranslatorDriver translator) {
        assert runtime != null;

        this.runtime = runtime;
        this.translator = translator;

        objectSpaceManager = new ObjectSpaceManager(this);
        traceManager = new TraceManager(this);

        // See note in CoreLibrary#initialize to see why we need to break this into two statements
        coreLibrary = new CoreLibrary(this);
        coreLibrary.initialize();

        featureManager = new FeatureManager(this);
        atExitManager = new AtExitManager();
        sourceManager = new SourceManager();

        rubyDebugManager = new RubyDebugManager();

        // Must initialize threads before fibers

        threadManager = new ThreadManager(this);
        fiberManager = new FiberManager(this);
    }

    public void load(Source source) {
        execute(this, source, TranslatorDriver.ParserContext.TOP_LEVEL, coreLibrary.getMainObject(), null);
    }

    public void loadFile(String fileName) {
        if (new File(fileName).isAbsolute()) {
            loadFileAbsolute(fileName);
        } else {
            loadFileAbsolute(this.getRuntime().getCurrentDirectory() + File.separator + fileName);
        }
    }

    private void loadFileAbsolute(String fileName) {
        final Source source = sourceManager.get(fileName);
        final String code = source.getCode();
        if (code == null) {
            throw new RuntimeException("Can't read file " + fileName);
        }
        coreLibrary.getLoadedFeatures().slowPush(makeString(fileName));
        execute(this, source, TranslatorDriver.ParserContext.TOP_LEVEL, coreLibrary.getMainObject(), null);
    }

    public RubySymbol.SymbolTable getSymbolTable() {
        return symbolTable;
    }

    public RubySymbol newSymbol(String name) {
        return symbolTable.getSymbol(name);
    }

    public RubySymbol newSymbol(ByteList name) {
        return symbolTable.getSymbol(name);
    }

    public Object eval(String code) {
        final Source source = sourceManager.get("(eval)", code);
        return execute(this, source, TranslatorDriver.ParserContext.TOP_LEVEL, coreLibrary.getMainObject(), null);
    }

    public Object eval(String code, RubyModule module) {
        final Source source = sourceManager.get("(eval)", code);
        return execute(this, source, TranslatorDriver.ParserContext.MODULE, module, null);
    }

    public Object eval(String code, RubyBinding binding) {
        final Source source = sourceManager.get("(eval)", code);
        return execute(this, source, TranslatorDriver.ParserContext.TOP_LEVEL, binding.getSelf(), binding.getFrame());
    }

    public void runShell(Node node, MaterializedFrame frame) {
        final BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));

        MaterializedFrame existingLocals = frame;

        String prompt = "Ruby> ";
        if (node != null) {
            final SourceSection src = node.getSourceSection();
            if (src != null) {
                prompt = (src.getSource().getName() + ":" + src.getStartLine() + "> ");
            }
        }

        while (true) {
            try {
                System.out.print(prompt);
                final String line = reader.readLine();

                final ShellResult result = evalShell(line, existingLocals);

                System.out.println("=> " + result.getResult());



                existingLocals = result.getFrame();
            } catch (BreakShellException e) {
                return;
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    public ShellResult evalShell(String code, MaterializedFrame existingLocals) {
        final Source source = sourceManager.get("(shell)", code);
        return (ShellResult) execute(this, source, TranslatorDriver.ParserContext.SHELL, coreLibrary.getMainObject(), existingLocals);
    }

    public Object execute(RubyContext context, Source source, TranslatorDriver.ParserContext parserContext, Object self, MaterializedFrame parentFrame) {
        try {
            final RubyParserResult parseResult = translator.parse(context, source, parserContext, parentFrame);
            final CallTarget callTarget = Truffle.getRuntime().createCallTarget(parseResult.getRootNode());
            return callTarget.call(RubyArguments.pack(parentFrame, self, null));
        } catch (RaiseException e) {
            throw e;
        } catch (ThrowException e) {
            throw new RaiseException(context.getCoreLibrary().argumentErrorUncaughtThrow(e.getTag()));
        } catch (BreakShellException | QuitException e) {
            throw e;
        } catch (Throwable e) {
            throw new RaiseException(ExceptionTranslator.translateException(this, e));
        }
    }

    public long getNextObjectID() {
        // TODO(CS): We can theoretically run out of long values

        final long id = nextObjectID.getAndIncrement();

        if (id < 0) {
            nextObjectID.set(Long.MIN_VALUE);
            throw new RuntimeException("Object IDs exhausted");
        }

        return id;
    }

    public void shutdown() {
        atExitManager.run();

        threadManager.leaveGlobalLock();

        objectSpaceManager.shutdown();

        if (fiberManager != null) {
            fiberManager.shutdown();
        }
    }

    public RubyString makeString(String string) {
        return RubyString.fromJavaString(coreLibrary.getStringClass(), string);
    }

    public RubyString makeString(char string) {
        return makeString(Character.toString(string));
    }

    public IRubyObject toJRuby(Object object) {
        if (object instanceof NilPlaceholder) {
            return runtime.getNil();
        } else if (object == getCoreLibrary().getKernelModule()) {
            return runtime.getKernel();
        } else if (object == getCoreLibrary().getMainObject()) {
            return runtime.getTopSelf();
        } else if (object instanceof Boolean) {
            return runtime.newBoolean((boolean) object);
        } else if (object instanceof Integer) {
            return runtime.newFixnum((int) object);
        } else if (object instanceof Double) {
            return runtime.newFloat((double) object);
        } else if (object instanceof RubyString) {
            return ((RubyString) object).toJRubyString();
        } else {
            throw getRuntime().newRuntimeError("cannot pass " + object + " to JRuby");
        }
    }

    public Object toTruffle(IRubyObject object) {
        if (object == runtime.getTopSelf()) {
            return getCoreLibrary().getMainObject();
        } else if (object == runtime.getKernel()) {
            return getCoreLibrary().getKernelModule();
        } else if (object instanceof RubyNil) {
            return NilPlaceholder.INSTANCE;
        } else if (object instanceof RubyBoolean.True) {
            return true;
        } else if (object instanceof RubyBoolean.False) {
            return false;
        } else if (object instanceof org.jruby.RubyFixnum) {
            final long value = ((org.jruby.RubyFixnum) object).getLongValue();

            if (value < Integer.MIN_VALUE || value > Integer.MAX_VALUE) {
                throw new UnsupportedOperationException();
            }

            return (int) value;
        } else if (object instanceof org.jruby.RubyFloat) {
            return ((org.jruby.RubyFloat) object).getDoubleValue();
        } else {
            throw object.getRuntime().newRuntimeError("cannot pass " + object.inspect() + " to Truffle");
        }
    }

    public Ruby getRuntime() {
        return runtime;
    }

    public CoreLibrary getCoreLibrary() {
        return coreLibrary;
    }

    public FeatureManager getFeatureManager() {
        return featureManager;
    }

    public ObjectSpaceManager getObjectSpaceManager() {
        return objectSpaceManager;
    }

    public TraceManager getTraceManager() {
        return traceManager;
    }

    public FiberManager getFiberManager() {
        return fiberManager;
    }

    public ThreadManager getThreadManager() {
        return threadManager;
    }

    public TranslatorDriver getTranslator() {
        return translator;
    }

    /**
     * Utility method to check if an object should be visible in a Ruby program. Used in assertions
     * at method boundaries to check that only values we want to be visible to the programmer become
     * so.
     */
    public static boolean shouldObjectBeVisible(Object object) {
        return object instanceof UndefinedPlaceholder || //
                        object instanceof Boolean || //
                        object instanceof Integer || //
                        object instanceof Long || //
                        object instanceof BigInteger || //
                        object instanceof Double || //
                        object instanceof RubyBasicObject || //
                        object instanceof NilPlaceholder;
    }

    public static boolean shouldObjectsBeVisible(Object... objects) {
        assert objects != null;

        for (Object object : objects) {
            if (!shouldObjectBeVisible(object)) {
                return false;
            }
        }

        return true;
    }

    public AtExitManager getAtExitManager() {
        return atExitManager;
    }

    public SourceManager getSourceManager() {
        return sourceManager;
    }

}
