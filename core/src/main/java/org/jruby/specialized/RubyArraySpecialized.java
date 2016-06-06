package org.jruby.specialized;

import org.jruby.Ruby;
import org.jruby.RubyArray;
import org.jruby.RubyClass;
import org.jruby.runtime.Block;
import org.jruby.runtime.Constants;
import org.jruby.runtime.ThreadContext;
import org.jruby.runtime.builtin.IRubyObject;

/**
 * Created by headius on 5/28/16.
 */
public abstract class RubyArraySpecialized extends RubyArray {
    public RubyArraySpecialized(Ruby runtime) {
        super(runtime, runtime.getArray());
    }

    public RubyArraySpecialized(RubyClass otherClass) {
        super(otherClass.getClassRuntime(), otherClass);
    }

//    @Override
//    public abstract IRubyObject eltSetOk(long offset, IRubyObject value);
//
//    @Override
//    public abstract IRubyObject eltInternal(int offset);
//
//    @Override
//    public abstract IRubyObject eltInternalSet(int offset, IRubyObject item);
//
//    @Override
//    public abstract IRubyObject dup();
//
//    @Override
//    public abstract IRubyObject each(ThreadContext context, Block block);
//
//    @Override
//    public abstract void copyInto(IRubyObject[] target, int start);
//
//    @Override
//    protected abstract IRubyObject fillCommon(ThreadContext context, int beg, long len, IRubyObject item);
//
//    @Override
//    protected abstract IRubyObject fillCommon(ThreadContext context, int beg, long len, Block block);

    protected abstract void fail();

    protected boolean ok() {
        return getFlag(Constants.ARRAY_PACKING_FAILED_F);
    }

    @Override
    public abstract RubyArray aryDup();
}
